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

      @name = name
      @max_fibers = max_fibers
      @queue = ::Thread::Queue.new
      @pending_count = Concurrent::AtomicFixnum.new(0)
      @mutex = Mutex.new
      @reactor_thread = nil
      @pid = ::Process.pid
    end

    # Enqueue a task, starting the reactor on first use.
    # @return [Boolean] whether the task was accepted
    def post(*args, &block)
      @mutex.synchronize do
        return false if @queue.closed?

        reset_after_fork if @pid != ::Process.pid
        @pending_count.increment
        @queue.push([args, block])
        @reactor_thread = spawn_reactor unless @reactor_thread&.alive?
        true
      end
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
      @mutex.synchronize { @queue.close }
    end

    # Discard queued tasks and request cancellation of running fibers.
    # @return [void]
    def kill
      thread = @mutex.synchronize do
        @queue.close
        @queue.clear
        @reactor_thread
      end
      thread.raise(Interrupt) if thread&.alive?
    end

    # Block until in-progress and enqueued tasks have finished.
    # @param timeout [Numeric, nil] seconds to wait, or +nil+ to wait forever
    # @return [Boolean] whether the executor fully stopped
    def wait_for_termination(timeout = nil)
      thread = @mutex.synchronize { @reactor_thread }
      thread.nil? || !thread.join(timeout).nil?
    end

    # @return [Integer] available capacity after counting running and queued tasks
    def ready_worker_count
      [@max_fibers - @pending_count.value, 0].max
    end

    # Fatal errors must not be contained or reported as ordinary task errors.
    # @return [Boolean]
    def self.fatal_exception?(error)
      error.is_a?(::SignalException) || error.is_a?(::SystemExit) || error.is_a?(::Async::Stop)
    end

    private

    def reactor_alive?
      @mutex.synchronize { @reactor_thread&.alive? } || false
    end

    def reset_after_fork
      @pid = ::Process.pid
      @queue.clear
      @pending_count.value = 0
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
          workers = Array.new(@max_fibers) { reactor.async { work_off_queue } }
          workers.each(&:wait)
        end
      end
    rescue Interrupt
      nil
    ensure
      @mutex.synchronize do
        @pending_count.value = @queue.size
        @reactor_thread = spawn_reactor unless @queue.empty?
      end
    end

    def work_off_queue
      while (args, block = @queue.pop)
        begin
          block.call(*args)
        rescue Exception => e # rubocop:disable Lint/RescueException
          raise if self.class.fatal_exception?(e)

          GoodJob._on_thread_error(e)
        ensure
          @pending_count.decrement
        end
      end
    end
  end
end
