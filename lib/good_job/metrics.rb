# frozen_string_literal: true

module GoodJob # :nodoc:
  # Metrics for the scheduler.
  class Metrics
    def initialize
      @empty_executions = Concurrent::AtomicFixnum.new
      @errored_executions = Concurrent::AtomicFixnum.new
      @succeeded_executions = Concurrent::AtomicFixnum.new
      @unexecutable_executions = Concurrent::AtomicFixnum.new
    end

    # Increments number of empty queried executions.
    # @return [Integer]
    def increment_empty_executions
      @empty_executions.increment
    end

    # Increments number of failed executions.
    # @return [Integer]
    def increment_errored_executions
      @errored_executions.increment
    end

    # Increments number of succeeded executions.
    # @return [Integer]
    def increment_succeeded_executions
      @succeeded_executions.increment
    end

    # Increments number of unlocked executions.
    # @return [Integer]
    def increment_unexecutable_executions
      @unexecutable_executions.increment
    end

    def to_h
      {
        empty_executions_count: @empty_executions.value,
        errored_executions_count: @errored_executions.value,
        succeeded_executions_count: @succeeded_executions.value,
        unexecutable_executions_count: @unexecutable_executions.value,
      }.tap do |values|
        values[:total_executions_count] = values.values.sum
      end
    end

    # Reset counters.
    # @return [void]
    def reset
      @empty_executions.value = 0
      @errored_executions.value = 0
      @succeeded_executions.value = 0
      @unexecutable_executions.value = 0
    end
  end
end
