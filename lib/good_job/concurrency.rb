# frozen_string_literal: true

require "farce"

module GoodJob
  # Concurrency primitives built on Farce, replacing the subset of
  # concurrent-ruby that GoodJob uses (executors, futures, scheduled and
  # timer tasks, and events).
  #
  # Farce provides queues, atoms, counters, flags and signals, but no executors
  # or futures, so those are implemented here on top of Farce's data structures.
  # GoodJob's objects hold Active Record state and are only used from the
  # Ractor that created them, so the +Farce::Unshared+ variants are used for
  # anything holding unshareable values (procs, schedulers, tasks).
  module Concurrency
    JRUBY = RUBY_ENGINE == "jruby"

    # Raised to observers when a pending task is cancelled.
    class CancelledOperationError < StandardError; end

    # Calls an observer with Concurrent-style arguments.
    # @!visibility private
    def self.notify(observer, func, time, value, reason)
      observer.public_send(func, time, value, reason)
    end

    # A one-shot latch that threads can wait on.
    class Event
      def initialize
        @flag = Farce::Flag.new(false)
        @signal = Farce::Signal.new
      end

      def set
        @flag.value = true
        @signal.broadcast
        true
      end

      def reset
        @flag.value = false
        true
      end

      def set?
        @flag.value
      end

      # @param timeout [Numeric, nil] seconds to wait, or forever when nil
      # @return [Boolean] whether the event is set
      def wait(timeout = nil)
        return true if set?

        @signal.wait_until(timeout: timeout) { @flag.value } ? true : false
      end
    end

    # A thread pool with the subset of +Concurrent::ThreadPoolExecutor+
    # behavior GoodJob relies on: lazily created workers up to +max_threads+,
    # an optional bounded queue that discards tasks when full, idle worker
    # reaping, and graceful or forceful shutdown.
    class ThreadPool
      attr_reader :name, :min_threads, :max_threads, :max_queue, :idletime

      def initialize(name: nil, min_threads: 0, max_threads: 1, max_queue: 0, idletime: 60, **_options)
        @name = name
        @min_threads = min_threads
        @max_threads = max_threads
        @max_queue = max_queue
        @idletime = idletime
        reset_state
      end

      # @return [Boolean] whether the task was accepted
      def post(*args, &task)
        raise ArgumentError, "no block given" unless task

        reset_state if @pid != ::Process.pid # worker threads do not survive a fork
        @lock.synchronize do
          return false unless running?

          if @inflight.value < @worker_count.value
            # an existing worker is or will soon be free
          elsif @worker_count.value < @max_threads
            spawn_worker
          elsif @max_queue.positive? && (@inflight.value - @worker_count.value) >= @max_queue
            return false
          end

          @inflight.increment
          @queue.push([task, args])
        end
        true
      end

      def <<(task)
        post(&task)
        self
      end

      # Number of threads that could start a task immediately.
      def ready_worker_count
        [@max_threads - @inflight.value, 0].max
      end

      def queue_length
        @queue.size
      end

      def length
        @worker_count.value
      end

      def running?
        @state.value == :running
      end

      def shuttingdown?
        @state.value == :shuttingdown
      end

      def shutdown?
        @state.value == :shutdown
      end

      # Stop accepting tasks; queued and running tasks are completed.
      def shutdown
        @lock.synchronize do
          return true unless @state.compare_and_set(:running, :shuttingdown)

          @queue.seal
          finish_shutdown if @worker_count.value.zero?
        end
        true
      end

      # Stop all workers immediately, abandoning queued tasks.
      def kill
        @lock.synchronize do
          @state.value = :shuttingdown unless shutdown?
          @queue.close
        end
        @workers.to_a.each(&:kill)
        @workers.to_a.each(&:join)
        @lock.synchronize { finish_shutdown }
        true
      end

      # @param timeout [Numeric, nil] seconds to wait, or forever when nil
      # @return [Boolean] whether the pool terminated within the timeout
      def wait_for_termination(timeout = nil)
        @terminated.wait(timeout)
      end

      private

      def reset_state
        @pid = ::Process.pid
        @queue = Farce::Unshared::Queue.new(capacity: nil)
        @state = Farce::Atom.new(:running)
        @workers = Farce::Unshared::Set.new
        @inflight = Farce::Counter.new
        @worker_count = Farce::Counter.new
        @lock = Farce::Lock.new
        @terminated = Event.new
        @thread_index = Farce::Counter.new
      end

      def spawn_worker
        @worker_count.increment
        index = @thread_index.increment
        thread = Thread.new { work }
        thread.name = "#{@name || 'good_job-pool'}-worker-#{index}"
        @workers << thread
      end

      def work
        retired = false
        loop do
          job = begin
            @queue.pop(timeout: @idletime)
          rescue Farce::ClosedQueueError
            nil
          end

          if job.nil?
            break unless running?

            retired = @lock.synchronize do
              next false unless @worker_count.value > @min_threads && @queue.empty?

              @worker_count.decrement
              true
            end
            break if retired

            next
          end

          task, args = job
          begin
            task.call(*args)
          rescue Exception # rubocop:disable Lint/RescueException
            # tasks are expected to handle their own errors
          ensure
            @inflight.decrement
          end
        end
      ensure
        @lock.synchronize do
          @workers.delete(Thread.current)
          @worker_count.decrement unless retired
          finish_shutdown if !running? && @worker_count.value.zero?
        end
      end

      def finish_shutdown
        @state.value = :shutdown
        @terminated.set
      end
    end

    # Runs scheduled callables on a single timer thread, ordered by Farce::TimerQueue.
    class TimerSet
      def initialize
        @queue = Farce::Unshared::TimerQueue.new
        @lock = Farce::Lock.new
        @thread = nil
        @running = Farce::Flag.new(true)
      end

      # @return [Array(Float, Object), nil] a handle that can be passed to {#cancel}
      def post(delay, callable)
        @lock.synchronize do
          return nil unless @running.value

          at = Farce.clock(in: delay.to_f)
          @queue.push(callable, at: at)
          ensure_thread
          [at, callable]
        end
      end

      def cancel(handle)
        at, callable = handle
        @queue.delete(callable, at: at)
      end

      def length
        @queue.size
      end

      def reset
        @queue.clear
      end

      def running?
        @running.value
      end

      def shutdown
        @lock.synchronize do
          @running.value = false
          @queue.close
        end
        true
      end

      def kill
        shutdown
      end

      private

      def ensure_thread
        return if @thread&.alive?

        @thread = Thread.new do
          loop do
            callable = @queue.pop
            begin
              callable.call
            rescue Exception # rubocop:disable Lint/RescueException
              # scheduled callables handle their own errors
            end
          end
        rescue Farce::ClosedQueueError
          nil
        end
        @thread.name = "good_job-timer"
      end
    end

    # A task that runs once on an executor and notifies observers with
    # +(time, value, reason)+ when it completes.
    class Future
      def initialize(args: [], executor: Concurrency.global_executor, &task)
        raise ArgumentError, "no block given" unless task

        @task = task
        @args = args
        @executor = executor
        @state = Farce::Atom.new(:unscheduled)
        @value = nil
        @reason = nil
        @observers = Farce::Unshared::Vector.new
        @completed = Event.new
      end

      attr_reader :reason

      def state
        @state.value
      end

      def add_observer(observer = nil, func = :call, &block)
        if block
          observer = block
          func = :call
        end
        @observers << [observer, func]
        observer
      end

      def execute
        return self unless @state.compare_and_set(:unscheduled, :pending)

        schedule
        self
      end

      def pending?
        %i[unscheduled pending].include?(state)
      end

      def unscheduled?
        state == :unscheduled
      end

      def processing?
        state == :processing
      end

      def fulfilled?
        state == :fulfilled
      end

      def rejected?
        state == :rejected
      end

      def cancelled?
        state == :cancelled
      end

      def complete?
        %i[fulfilled rejected cancelled].include?(state)
      end
      alias incomplete_or_complete? complete?

      def wait(timeout = nil)
        @completed.wait(timeout)
        self
      end

      def value(timeout = nil)
        wait(timeout)
        @value
      end

      # Cancel the task if it has not started running.
      # @return [Boolean]
      def cancel
        return false unless @state.compare_and_set(:pending, :cancelled) || @state.compare_and_set(:unscheduled, :cancelled)

        unschedule
        complete(nil, CancelledOperationError.new)
        true
      end

      # @!visibility private
      def run
        return unless @state.compare_and_set(:pending, :processing)

        value = nil
        reason = nil
        begin
          value = @task.call(*@args)
        rescue StandardError => e
          reason = e
        end
        @state.value = reason ? :rejected : :fulfilled
        complete(value, reason)
      end

      private

      def schedule
        post_to_executor
      end

      def post_to_executor
        accepted = @executor.post { run }
        return if accepted != false

        # Discarded by the executor (full or shut down). Like Concurrent's :discard policy, observers are not notified.
        @completed.set if @state.compare_and_set(:pending, :rejected)
      end

      def unschedule
      end

      def complete(value, reason)
        @value = value
        @reason = reason
        @completed.set
        time = Time.current
        @observers.to_a.each { |observer, func| Concurrency.notify(observer, func, time, value, reason) }
      end
    end

    # A {Future} that is posted to its executor after a delay.
    class ScheduledTask < Future
      def initialize(delay, timer_set: Concurrency.global_timer_set, **options, &task)
        super(**options, &task)
        @delay = delay.to_f
        @timer_set = timer_set
        @handle = nil
      end

      private

      def schedule
        return super if @delay <= 0

        @handle = @timer_set.post(@delay, -> { post_to_executor })
        complete(nil, CancelledOperationError.new) if @handle.nil? && @state.compare_and_set(:pending, :cancelled)
      end

      def unschedule
        @timer_set.cancel(@handle) if @handle
      end
    end

    # Repeatedly runs a block on its own thread every +execution_interval+ seconds.
    class TimerTask
      def self.execute(**options, &task)
        new(**options, &task).tap(&:execute)
      end

      def initialize(execution_interval:, run_now: false, **_options, &task)
        raise ArgumentError, "no block given" unless task

        @task = task
        @execution_interval = execution_interval
        @run_now = run_now
        @state = Farce::Atom.new(:unscheduled)
        @stop = Event.new
        @terminated = Event.new
        @observers = Farce::Unshared::Vector.new
        @thread = nil
      end

      def add_observer(observer = nil, func = :call, &block)
        if block
          observer = block
          func = :call
        end
        @observers << [observer, func]
        observer
      end

      def execute
        return self unless @state.compare_and_set(:unscheduled, :running)

        @thread = Thread.new { run_loop }
        @thread.name = "good_job-timer-task"
        self
      end

      def running?
        @state.value == :running
      end

      def shuttingdown?
        @state.value == :shuttingdown
      end

      def shutdown?
        @state.value == :shutdown
      end

      def shutdown
        @state.value = :shutdown if @state.compare_and_set(:unscheduled, :shutdown)
        @stop.set if @state.compare_and_set(:running, :shuttingdown)
        true
      end

      def kill
        shutdown
        @thread&.kill
        @thread&.join
        finish
        true
      end

      def wait_for_termination(timeout = nil)
        return true if shutdown?

        @terminated.wait(timeout)
      end

      private

      def run_loop
        tick if @run_now
        tick until @stop.wait(@execution_interval)
      ensure
        finish
      end

      def tick
        value = nil
        reason = nil
        begin
          value = @task.call(self)
        rescue StandardError => e
          reason = e
        end
        time = Time.current
        @observers.to_a.each { |observer, func| Concurrency.notify(observer, func, time, value, reason) }
      end

      def finish
        @state.value = :shutdown
        @terminated.set
      end
    end

    GLOBAL_EXECUTOR = Farce::Unshared::Lazy.new { ThreadPool.new(name: "good_job-global", max_threads: 10_000, idletime: 60) }
    GLOBAL_TIMER_SET = Farce::Unshared::Lazy.new { TimerSet.new }
    private_constant :GLOBAL_EXECUTOR, :GLOBAL_TIMER_SET

    # An effectively unbounded pool for long-lived or I/O-bound tasks, like +Concurrent.global_io_executor+.
    # @return [ThreadPool]
    def self.global_executor
      GLOBAL_EXECUTOR.value
    end

    # @return [TimerSet]
    def self.global_timer_set
      GLOBAL_TIMER_SET.value
    end
  end
end
