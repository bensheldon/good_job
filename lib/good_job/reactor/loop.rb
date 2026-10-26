# frozen_string_literal: true

module GoodJob
  class Reactor
    # A single thread that runs one thing at a time: posted tasks, IO watcher
    # callbacks, and timers. Its state is only touched on its own thread; other
    # threads hand it work through a queue and wake it with a self-pipe.
    class Loop
      # A registered watcher or timer, canceled with #cancel.
      class Handle
        def initialize(loop)
          @loop = loop
          @canceled = Concurrent::AtomicBoolean.new(false)
        end

        def cancel
          @loop.wake if @canceled.make_true
          nil
        end

        def canceled?
          @canceled.true?
        end
      end

      # @!visibility private
      class Timer < Handle
        attr_reader :due, :interval

        def initialize(loop, due, interval, callback)
          super(loop)
          @due = due
          @interval = interval
          @callback = callback
        end

        def fire(now)
          @callback.call
        ensure
          if (interval = @interval)
            @due = now + interval
          else
            cancel
          end
        end
      end

      # @!visibility private
      class Watcher < Handle
        attr_reader :io

        def initialize(loop, io, callback)
          super(loop)
          @io = io
          @callback = callback
        end

        def fire
          @callback.call
        end
      end

      attr_reader :clock

      def initialize(name: "pebble_bed", clock: Clock.new)
        @name = name
        @clock = clock
        @queue = Thread::Queue.new
        @timers = []
        @watchers = []
        @wake_reader, @wake_writer = IO.pipe
        @error_handlers = []
        @running = Concurrent::AtomicBoolean.new(false)
        @thread = nil
        @transition = Mutex.new
        @starts = 0
        advancing = _ = clock
        advancing.on_advance { wake } if advancing.respond_to?(:on_advance)
      end

      # Counts a start; the first start launches the thread.
      def start
        @transition.synchronize do
          @starts += 1
          start_thread if @starts == 1
        end
        self
      end

      # Counts a stop; the stop that balances the last start stops the thread.
      # With `force: true`, stops regardless of outstanding starts. Returns whether
      # the thread has stopped.
      def stop(timeout: 10, force: false)
        @transition.synchronize do
          return true if @starts.zero?

          @starts = force ? 0 : @starts - 1
          @starts.zero? ? stop_thread(timeout) : true
        end
      end

      def running?
        @running.true?
      end

      # Whether the thread is still running, which it can be briefly after #running? becomes false.
      def alive?
        @thread&.alive? || false
      end

      def on_thread?
        !@thread.nil? && Thread.current == @thread
      end

      # Runs the block on the loop thread and returns its Result. Called from the
      # loop thread, it runs immediately, so the Result is already resolved.
      def post(&block)
        result = Result.new
        dispatch do
          result.fulfill(block.call)
        rescue Exception => e # rubocop:disable Lint/RescueException
          result.reject(e)
        end
        result
      end

      # Calls the block whenever `io` is readable.
      def watch(io, &block)
        watcher = Watcher.new(self, io, guard(block))
        dispatch { @watchers << watcher }
        watcher
      end

      def after(seconds, &block)
        schedule(seconds, nil, block)
      end

      def every(seconds, &block)
        schedule(seconds, seconds, block)
      end

      # Errors raised by watchers and timers registered directly on the loop.
      def on_error(&block)
        @error_handlers << block
        self
      end

      def wake
        @wake_writer.write_nonblock(".", exception: false)
      rescue IOError
        nil
      end

      # @!visibility private
      # Runs the block on the loop thread: immediately when called from it,
      # otherwise queued.
      def dispatch(&block)
        if on_thread?
          block.call
        else
          enqueue!(block)
        end
        nil
      end

      # @!visibility private
      # Queues the block to run on the loop thread after the current work, even
      # when called from the loop thread. Returns false if the loop is stopped.
      def defer(&block)
        return false unless running?

        @queue << block
        wake
        true
      end

      # @!visibility private
      def report_error(error)
        if @error_handlers.empty?
          warn("#{@name}: #{error.class}: #{error.message}")
        else
          @error_handlers.each { |handler| handler.call(error) }
        end
      end

      private

      def enqueue!(block)
        raise NotRunningError, "#{@name} is not running" unless running?

        @queue << block
        wake
      end

      def schedule(seconds, interval, block)
        timer = Timer.new(self, @clock.now + seconds, interval, guard(block))
        dispatch { @timers << timer }
        timer
      end

      def guard(block)
        lambda do
          block.call
        rescue Exception => e # rubocop:disable Lint/RescueException
          report_error(e)
        end
      end

      def start_thread
        @thread&.join unless on_thread?
        @wake_reader, @wake_writer = IO.pipe if @wake_reader.closed?
        @running.make_true
        thread = Thread.new { run }
        thread.name = @name
        @thread = thread
      end

      def stop_thread(timeout)
        @running.make_false
        wake
        thread = @thread
        return true if on_thread? || thread.nil?

        !thread.join(timeout).nil?
      end

      def run
        while running?
          run_due_timers
          drain_queue
          break unless running?

          wait_for_activity
        end
      ensure
        drain_queue
        @timers.clear
        @watchers.clear
        @wake_writer.close
        @wake_reader.close
      end

      def drain_queue
        until @queue.empty?
          begin
            @queue.pop(true)&.call
          rescue ThreadError
            break
          rescue Exception => e # rubocop:disable Lint/RescueException
            report_error(e)
          end
        end
      end

      def run_due_timers
        now = @clock.now
        @timers.select { |timer| !timer.canceled? && timer.due <= now }.sort_by(&:due).each { |timer| timer.fire(now) }
        @timers.reject!(&:canceled?)
      end

      # A watched IO closed by another thread while selecting raises; the closed
      # IO is pruned on the next pass.
      def wait_for_activity
        @watchers.reject! { |watcher| watcher.canceled? || watcher.io.closed? }
        readers = [@wake_reader, *@watchers.map(&:io)] #: Array[IO]
        # Steep can't infer IO.select's types for the unused write and error arrays.
        readable, = begin
          IO.select(readers, nil, nil, next_timeout) # steep:ignore UnresolvedOverloading
        rescue IOError, Errno::EBADF
          nil
        end
        return unless readable

        drain_wake_reader if readable.include?(@wake_reader)
        @watchers.each { |watcher| watcher.fire if !watcher.canceled? && readable.include?(watcher.io) }
      end

      def next_timeout
        due = @timers.reject(&:canceled?).map(&:due).min
        return nil if due.nil?

        [due - @clock.now, 0.0].max
      end

      def drain_wake_reader
        loop { break unless @wake_reader.read_nonblock(1024, exception: false).is_a?(String) }
      end
    end
  end
end
