# frozen_string_literal: true
module GoodJob # :nodoc:
  # Metrics for the scheduler.
  class Metrics
    def initialize
      @failed_count = Concurrent::AtomicFixnum.new
      @succeeded_count = Concurrent::AtomicFixnum.new
    end

    # Increments number of failed jobs.
    # @return [Integer]
    def increment_failed
      @failed_count.increment
    end

    # Increments number of succeeded jobs.
    # @return [Integer]
    def increment_succeeded
      @succeeded_count.increment
    end

    # Failed job count.
    # @return [Integer]
    def failed_count
      @failed_count.value
    end

    # Number of succeeded jobs.
    # @return [Integer]
    def succeeded_count
      @succeeded_count.value
    end

    # Total number of jobs (failed + succeeded).
    # @return [Integer]
    def total_count
      failed_count + succeeded_count
    end

    # Reset counters.
    # @return [void]
    def reset
      @failed_count.value = 0
      @succeeded_count.value = 0
    end
  end
end
