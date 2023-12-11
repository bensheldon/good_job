# frozen_string_literal: true

require 'concurrent/atomic/atomic_fixnum'

module GoodJob # :nodoc:
  class JobPerformer
    # Metrics for the scheduler.
    class Metrics
      def initialize
        @mutex = Mutex.new
        @empty_executions = Concurrent::AtomicFixnum.new
        @errored_executions = Concurrent::AtomicFixnum.new
        @succeeded_executions = Concurrent::AtomicFixnum.new
        @execution_at = nil
        @check_queue_at = nil
      end

      # Increments number of failed executions.
      # @return [Integer]
      def increment_errored_executions
        @execution_at = Time.current
        @errored_executions.increment
      end

      # Increments number of succeeded executions.
      # @return [Integer]
      def increment_succeeded_executions
        @execution_at = Time.current
        @succeeded_executions.increment
      end

      # Increments number of dequeue attempts with no executions.
      # @return [Integer]
      def increment_empty_executions
        @empty_executions.increment
      end

      # Last time a job was executed (started or finished).
      # @return [Time, nil]
      def touch_execution_at
        @execution_at = Time.current
      end

      # Last time the queue was checked for jobs.
      # @return [Time, nil]
      def touch_check_queue_at
        @check_queue_at = Time.current
      end

      # All metrics in a Hash.
      # @return [Hash]
      def to_h
        {
          empty_executions_count: @empty_executions.value,
          errored_executions_count: @errored_executions.value,
          succeeded_executions_count: @succeeded_executions.value,
        }.tap do |values|
          values[:total_executions_count] = values[:succeeded_executions_count] + values[:errored_executions_count]
          values[:execution_at] = @execution_at
          values[:check_queue_at] = @check_queue_at
        end
      end

      # Reset counters.
      # @return [void]
      def reset
        @empty_executions.value = 0
        @errored_executions.value = 0
        @succeeded_executions.value = 0
        @execution_at = nil
        @check_queue_at = nil
      end
    end
  end
end
