# frozen_string_literal: true

require "concurrent/atomic/atomic_fixnum"
require "concurrent/executor/executor_service"

module GoodJob # :nodoc:
  #
  # Executes tasks as fibers on one +async+ reactor thread. Implements the
  # executor interface used by {Scheduler}, +Concurrent::ScheduledTask+,
  # and +Concurrent::Future+.
  #
  # @private
  class FiberPoolExecutor
    include Concurrent::ExecutorService

    # @return [String] name of the executor, used for the reactor thread name
    attr_reader :name

    # @return [Integer] maximum number of concurrently executing fibers
    attr_reader :max_fibers

    # @param max_fibers [Integer] maximum number of concurrently executing fibers
    # @param name [String, nil] name for the reactor thread
    def initialize(max_fibers:, name: nil)
      raise ArgumentError, "max_fibers must be at least 1, but was #{max_fibers.inspect}" unless max_fibers.is_a?(Integer) && max_fibers >= 1

      require "async"
      require "async/semaphore"
      self.class.consume_io_buffer_warning

      @name = name
      @max_fibers = max_fibers
      @queue = ::Thread::Queue.new
      @wakeup_reader, @wakeup_writer = ::IO.pipe
      @pending_count = Concurrent::AtomicFixnum.new(0)
      @mutex = Mutex.new
      @reactor_thread = nil
      @killed = false
      @pid = ::Process.pid
    end

    # Suppress +IO::Buffer+'s first-use warning before jobs perform IO.
    def self.consume_io_buffer_warning
      return if @io_buffer_warning_consumed || !defined?(::IO::Buffer)

      @io_buffer_warning_consumed = true
      original = Warning[:experimental]
      Warning[:experimental] = false
      begin
        ::IO::Buffer.new(1).free
      ensure
        Warning[:experimental] = original
      end
    end

    # Enqueue a task, starting the reactor on first use.
    # The queue is unbounded because +Concurrent::TimerSet+ does not retry
    # rejected tasks. A semaphore limits concurrent execution.
    # @return [Boolean] whether the task was accepted
    def post(*args, &block)
      return false if @queue.closed?

      # Queue insertion and pending counts must stay in sync with reactor recovery.
      accepted = @mutex.synchronize do
        reset_after_fork if @pid != ::Process.pid
        @pending_count.increment
        begin
          @queue.push([args, block])
        rescue ClosedQueueError
          @pending_count.decrement
          next false
        end
        spawn_reactor unless @reactor_thread&.alive?
        true
      end
      wake_reactor if accepted
      accepted
    end

    # @return [Boolean] whether the executor is accepting new tasks
    def running?
      !@queue.closed?
    end

    # @return [Boolean] whether the executor is stopping but still executing tasks
    def shuttingdown?
      @queue.closed? && reactor_alive?
    end

    # @return [Boolean] whether the executor has fully stopped
    def shutdown?
      @queue.closed? && !reactor_alive?
    end

    # Stop accepting tasks and finish accepted work.
    # @return [void]
    def shutdown
      thread = @mutex.synchronize do
        @queue.close
        thread = @reactor_thread
        close_wakeup_pipe unless thread&.alive?
        thread
      end
      wake_reactor if thread&.alive?
    end

    # Discard queued tasks and request cancellation of running fibers.
    # @return [void]
    def kill
      thread = @mutex.synchronize do
        return if @killed

        @killed = true
        @queue.close
        @queue.clear
        thread = @reactor_thread
        unless thread&.alive?
          @pending_count.value = 0
          close_wakeup_pipe
        end
        thread
      end
      # Async keeps IO available during cancellation so ensure blocks can release locks.
      thread&.raise(Interrupt)
    end

    # Block until in-progress and enqueued tasks have finished.
    # @param timeout [Numeric, nil] seconds to wait, or +nil+ to wait forever
    # @return [Boolean] whether the executor fully stopped
    def wait_for_termination(timeout = nil)
      deadline = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + timeout if timeout
      loop do
        thread = @mutex.synchronize { @reactor_thread }
        return true unless thread&.alive?

        remaining = deadline - ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) if deadline
        return false if remaining && remaining <= 0 && thread.alive?
        return false unless thread.join(remaining && [remaining, 0].max)
      end
    end

    # @return [Integer] available capacity after counting running and queued tasks
    def ready_worker_count
      count = @max_fibers - @pending_count.value
      count.positive? ? count : 0
    end

    # Defer a callback until the current task releases its capacity.
    # +Concurrent::ScheduledTask+ observers run before that release.
    # @return [Boolean] whether the callback was deferred
    def defer_after_current_task(&block)
      return false unless block

      callbacks = Thread.current[:good_job_fiber_pool_executor_callbacks]
      return false unless callbacks

      callbacks << block
      true
    end

    # Fatal errors must not be contained or reported as ordinary task errors.
    # Async may handle cancellation without shutting down the executor.
    # @return [Boolean]
    def self.fatal_exception?(error)
      error.is_a?(::SystemExit) || error.is_a?(::SignalException) ||
        (defined?(::Async::Stop) && error.is_a?(::Async::Stop)) ||
        (defined?(::Async::Cancel) && error.is_a?(::Async::Cancel)) || false
    end

    private

    def reactor_alive?
      thread = @mutex.synchronize { @reactor_thread }
      !thread.nil? && thread.alive?
    end

    # Inherited tasks and pipes belong to the parent. Requires +@mutex+.
    def reset_after_fork
      @pid = ::Process.pid
      @queue.clear
      @pending_count.value = 0
      @reactor_thread = nil
      close_wakeup_pipe
      @wakeup_reader, @wakeup_writer = ::IO.pipe
    end

    # Must be called while holding +@mutex+.
    def spawn_reactor
      @wakeup_reader, @wakeup_writer = ::IO.pipe if @wakeup_reader.closed? || @wakeup_writer.closed?
      # Defer interrupts until run_reactor can ensure resource cleanup.
      Thread.handle_interrupt(Object => :never) do
        @reactor_thread = ::Thread.new { run_reactor }
      end
    end

    # A full pipe already has a pending wakeup; a closed pipe needs none.
    def wake_reactor
      @wakeup_writer.write_nonblock("!")
    rescue IO::WaitWritable, IOError, Errno::EPIPE
      nil
    end

    # The IO wait lets job fibers resume while the reactor waits for new work.
    def run_reactor
      ::Thread.current.name = "#{name}-reactor"
      reader = @wakeup_reader
      read_buffer = ::String.new

      Thread.handle_interrupt(Object => :immediate) do
        Async do |reactor|
          semaphore = Async::Semaphore.new(@max_fibers, parent: reactor)

          loop do
            until @queue.empty?
              semaphore.async do
                # Keep work queued until capacity is available so it survives reactor failure.
                item = pop_nonblock
                next unless item

                args, block = item
                callbacks = []
                Thread.current[:good_job_fiber_pool_executor_callbacks] = callbacks
                block.call(*args)
              rescue Exception => e # rubocop:disable Lint/RescueException
                raise if self.class.fatal_exception?(e)

                # An unhandled task error would cancel every fiber on the reactor.
                GoodJob._on_thread_error(e)
              ensure
                @pending_count.decrement if item
                callbacks&.each do |callback|
                  callback.call
                rescue StandardError => e
                  GoodJob._on_thread_error(e)
                end
              end
            end

            break if @queue.closed?

            reader.wait_readable
            begin
              reader.read_nonblock(4096, read_buffer)
            rescue IO::WaitReadable
              nil
            rescue EOFError
              break
            end
          end
        end.wait
      end
    rescue Interrupt
      raise unless @killed
    rescue Exception => e # rubocop:disable Lint/RescueException
      raise if self.class.fatal_exception?(e)

      GoodJob._on_thread_error(e)
    ensure
      # Recover pending counts and tasks posted while the failing reactor was still alive.
      @mutex.synchronize do
        @pending_count.value = @queue.size
        @reactor_thread = nil if @reactor_thread == ::Thread.current
        if !@killed && !@queue.empty? && @reactor_thread.nil?
          spawn_reactor
        elsif @reactor_thread.nil?
          close_wakeup_pipe(reader, @wakeup_writer)
        end
      end
    end

    def close_wakeup_pipe(reader = @wakeup_reader, writer = @wakeup_writer)
      [reader, writer].each do |io|
        io.close unless io.closed?
      rescue IOError
        nil
      end
    end

    def pop_nonblock
      return if @queue.empty?

      @queue.pop(true)
    rescue ThreadError
      nil
    end
  end
end
