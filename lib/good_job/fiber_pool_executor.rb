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

    # @return [Integer] maximum number of concurrently executing tasks
    attr_reader :max_fibers

    # @param max_fibers [Integer] maximum number of concurrently executing fibers
    # @param name [String, nil] name for the reactor thread
    def initialize(max_fibers:, name: nil)
      raise ArgumentError, "max_fibers must be at least 1, but was #{max_fibers.inspect}" unless max_fibers.is_a?(Integer) && max_fibers >= 1

      require "async"

      @name = name
      @max_fibers = max_fibers
      @queue = ::Thread::Queue.new
      @pending_count = Concurrent::AtomicFixnum.new(0)
      @active_count = Concurrent::AtomicFixnum.new(0)
      # running accepts work; draining finishes it; stopping cancels it;
      # stopped has no replacement reactor. Transitions are protected by @mutex.
      @state = :running
      @mutex = Mutex.new
      @reactor_thread = nil
      @pid = ::Process.pid
    end

    # Enqueue a task, starting the reactor on first use. Match Scheduler's
    # thread pool allowance: N executing tasks plus N queued tasks, for 2N
    # accepted, unfinished tasks. The bound limits memory use when producers
    # race or scheduled tasks become runnable together. Admission and increment
    # share the mutex so concurrent producers cannot exceed that allowance.
    # Excess submissions are discarded, as with the thread pool.
    # @return [Boolean] whether the task was accepted
    def post(*args, &block)
      @mutex.synchronize do
        reset_after_fork if @pid != ::Process.pid
        return false unless @state == :running
        return false if @pending_count.value >= @max_fibers * 2

        @pending_count.increment
        @queue.push([args, block])
        @reactor_thread = spawn_reactor unless @reactor_thread&.alive?
        true
      end
    end

    # @return [Boolean] whether the executor is accepting new tasks
    def running?
      @mutex.synchronize { @state == :running }
    end

    # @return [Boolean] whether the executor is stopping but still executing tasks
    def shuttingdown?
      @mutex.synchronize { @state != :running && reactor_alive_without_lock? }
    end

    # @return [Boolean] whether the executor has fully stopped
    def shutdown?
      @mutex.synchronize { @state != :running && !reactor_alive_without_lock? }
    end

    # Stop accepting tasks and finish accepted work.
    # @return [void]
    def shutdown
      @mutex.synchronize do
        @state = reactor_alive_without_lock? ? :draining : :stopped if @state == :running
        @queue.close
      end
    end

    # Discard queued tasks and request cancellation of running fibers.
    # @return [void]
    def kill
      thread = @mutex.synchronize do
        @state = reactor_alive_without_lock? ? :stopping : :stopped
        @queue.close
        @pending_count.increment(-@queue.size)
        @queue.clear
        @reactor_thread
      end
      thread.raise(Interrupt) if thread&.alive?
    end

    # Block until in-progress and enqueued tasks have finished.
    # @param timeout [Numeric, nil] seconds to wait, or +nil+ to wait forever
    # @return [Boolean] whether the executor fully stopped
    def wait_for_termination(timeout = nil)
      deadline = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + timeout if timeout

      loop do
        thread = @mutex.synchronize { @reactor_thread }
        return true unless thread

        remaining = [deadline - ::Process.clock_gettime(::Process::CLOCK_MONOTONIC), 0].max if deadline
        return false unless thread.join(remaining)
        return true if @mutex.synchronize { @reactor_thread == thread }
      end
    end

    # Reserve capacity for queued tasks as well as executing tasks, so scheduler
    # wakeups do not keep submitting work already covered by accepted tasks.
    # @return [Integer] available capacity after counting running and queued tasks
    def ready_worker_count
      [@max_fibers - @pending_count.value, 0].max
    end

    # Executing tasks, excluding queued submissions and idle worker fibers.
    def active_worker_count
      @active_count.value
    end

    # Accepted tasks waiting for a worker.
    def queue_length
      [@pending_count.value - @active_count.value, 0].max
    end

    # Fatal errors must not be contained or reported as ordinary task errors.
    # @return [Boolean]
    def self.fatal_exception?(error)
      error.is_a?(::SignalException) || error.is_a?(::SystemExit) || error.is_a?(::Async::Stop)
    end

    private

    def reactor_alive_without_lock?
      @reactor_thread&.alive? || false
    end

    def reset_after_fork
      @pid = ::Process.pid
      @queue.clear
      @pending_count.value = 0
      @active_count.value = 0
      @reactor_thread = nil
    end

    # Defer interrupts until run_reactor can rescue them.
    def spawn_reactor
      ::Thread.handle_interrupt(Object => :never) { ::Thread.new { run_reactor } }
    end

    def run_reactor
      ::Thread.current.name = "#{name}-reactor"
      ::Thread.handle_interrupt(Object => :immediate) do
        Sync do |reactor|
          workers = Array.new(@max_fibers) { reactor.async { |worker| work_off_queue(worker) } }
          workers.each(&:wait)
        end
      end
    rescue Interrupt
      nil
    ensure
      @mutex.synchronize do
        @active_count.value = 0
        @pending_count.value = @queue.size
        if @state != :stopping && !@queue.empty?
          @reactor_thread = spawn_reactor
        elsif @state != :running
          @state = :stopped
        end
      end
    end

    # Each task runs in a child fiber so that cancelling it (e.g. +Async::Task.current.stop+)
    # ends only that task, not the worker, preserving pool capacity.
    def work_off_queue(worker)
      while (args, block = @queue.pop)
        @active_count.increment
        begin
          worker.async { |task| run_task(args, block, task) }.wait
        ensure
          @active_count.decrement
          @pending_count.decrement
        end
      end
    end

    # Capture the tree before cancellation can reparent unfinished descendants.
    def descendants(task)
      task.children.to_a.flat_map { |child| [child, *descendants(child)] }
    end

    def run_task(args, block, task)
      block.call(*args)
    rescue Exception => e # rubocop:disable Lint/RescueException
      raise if self.class.fatal_exception?(e)

      GoodJob._on_thread_error(e)
    ensure
      children = descendants(task)
      task.children.to_a.each(&:stop)
      children.each(&:wait)
    end
  end
end
