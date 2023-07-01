# frozen_string_literal: true
module GoodJob # :nodoc:
  # Metrics for the scheduler.
  class Metrics
    def initialize
      @empty_executions_count = Concurrent::AtomicFixnum.new
      @errored_executions_count = Concurrent::AtomicFixnum.new
      @succeeded_executions_count = Concurrent::AtomicFixnum.new
      @unlocked_executions_count = Concurrent::AtomicFixnum.new
    end

    # Increments number of empty queried executions.
    # @return [Integer]
    def increment_empty_executions
      @empty_executions_count.increment
    end

    # Increments number of failed executions.
    # @return [Integer]
    def increment_errored_executions
      @errored_executions_count.increment
    end

    # Increments number of succeeded executions.
    # @return [Integer]
    def increment_succeeded_executions
      @succeeded_executions_count.increment
    end

    # Increments number of unlocked executions.
    # @return [Integer]
    def increment_unlocked_executions
      @unlocked_executions_count.increment
    end

    # Number of empty executions.
    # @return [Integer]
    def empty_executions_count
      @empty_executions_count.value
    end

    # Number of failed executions.
    # @return [Integer]
    def errored_executions_count
      @errored_executions_count.value
    end

    # Number of succeeded executions.
    # @return [Integer]
    def succeeded_executions_count
      @succeeded_executions_count.value
    end

    # Number of unlocked executions.
    # @return [Integer]
    def unlocked_executions_count
      @unlocked_executions_count.value
    end

    # Number of all attempted executions.
    # @return [Numeric]
    def total_executions_count
      empty_executions_count + errored_executions_count + succeeded_executions_count + unlocked_executions_count
    end

    def to_h
      {
        empty_executions_count: empty_executions_count,
        errored_executions_count: errored_executions_count,
        succeeded_executions_count: succeeded_executions_count,
        unlocked_executions_count: unlocked_executions_count,
        total_executions_count: total_executions_count
      }
    end

    # Reset counters.
    # @return [void]
    def reset
      @errored_executions_count.value = 0
      @succeeded_executions_count.value = 0
    end
  end
end
