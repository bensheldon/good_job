# frozen_string_literal: true

module GoodJob
  class SharedExecutor
    MAX_THREADS = 2

    # @!attribute [r] instances
    #   @!scope class
    #   List of all instantiated SharedExecutor in the current process.
    #   @return [Array<GoodJob::SharedExecutor>, nil]
    cattr_reader :instances, default: Concurrent::Array.new, instance_reader: false

    attr_reader :executor

    def initialize
      self.class.instances << self
      create_executor
    end

    def running?
      @executor&.running?
    end

    def shutdown?
      if @executor
        @executor.shutdown?
      else
        true
      end
    end

    # Shut down the SharedExecutor.
    # Use {#shutdown?} to determine whether threads have stopped.
    # @param timeout [Numeric, nil] Seconds to wait for active threads.
    #   * +nil+, the scheduler will trigger a shutdown but not wait for it to complete.
    #   * +-1+, the scheduler will wait until the shutdown is complete.
    #   * +0+, the scheduler will immediately shutdown and stop any threads.
    #   * A positive number will wait that many seconds before stopping any remaining active threads.
    # @return [void]
    def shutdown(timeout: -1)
      return if @executor.nil? || @executor.shutdown?

      @executor.shutdown if @executor.running?

      if @executor.shuttingdown? && timeout # rubocop:disable Style/GuardClause
        executor_wait = timeout.negative? ? nil : timeout
        @executor.kill unless @executor.wait_for_termination(executor_wait)
      end
    end

    def restart(timeout: -1)
      shutdown(timeout: timeout) if running?
      create_executor
    end

    private

    def create_executor
      @executor = Concurrent::ThreadPoolExecutor.new(
        min_threads: 0,
        max_threads: MAX_THREADS,
        auto_terminate: true,
        idletime: 60,
        max_queue: 0,
        fallback_policy: :discard
      )
    end
  end
end
