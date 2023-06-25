# frozen_string_literal: true
module GoodJob # :nodoc:
  # Metrics for the scheduler.
  class Metrics
    def initialize
      @failed_executions_count = Concurrent::AtomicFixnum.new
      @succeeded_executions_count = Concurrent::AtomicFixnum.new
    end

    # Increments number of failed executions.
    # @return [Integer]
    def increment_failed_executions
      @failed_executions_count.increment
    end

    # Increments number of succeeded executions.
    # @return [Integer]
    def increment_succeeded_executions
      @succeeded_executions_count.increment
    end

    # Failed executions count.
    # @return [Integer]
    def failed_executions_count
      @failed_executions_count.value
    end

    # Number of succeeded executions.
    # @return [Integer]
    def succeeded_executions_count
      @succeeded_executions_count.value
    end

    # Total number of executions (failed + succeeded).
    # @return [Integer]
    def total_executions_count
      failed_executions_count + succeeded_executions_count
    end

    # Reset counters.
    # @return [void]
    def reset
      @failed_executions_count.value = 0
      @succeeded_executions_count.value = 0
    end
  end
end
