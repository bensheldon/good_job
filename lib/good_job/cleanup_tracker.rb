# frozen_string_literal: true

module GoodJob # :nodoc:
  # Tracks thresholds for cleaning up old jobs.
  class CleanupTracker
    attr_accessor :cleanup_interval_seconds,
                  :cleanup_interval_jobs,
                  :job_count,
                  :last_at

    def initialize(cleanup_interval_seconds: false, cleanup_interval_jobs: false)
      raise ArgumentError, "Do not use `0`. Use `false` to disable, or -1 to always run" if cleanup_interval_seconds == 0 || cleanup_interval_jobs == 0 # rubocop:disable Style/NumericPredicate

      self.cleanup_interval_seconds = cleanup_interval_seconds
      self.cleanup_interval_jobs = cleanup_interval_jobs

      reset
    end

    # Increments job count.
    # @return [Integer]
    def increment
      self.job_count += 1
    end

    # Whether a cleanup should be run.
    # @return [Boolean]
    def cleanup?
      (cleanup_interval_jobs && job_count > cleanup_interval_jobs) ||
        (cleanup_interval_seconds && last_at < Time.current - cleanup_interval_seconds) ||
        false
    end

    # Resets the counters.
    # @return [void]
    def reset
      self.job_count = 0
      self.last_at = Time.current
    end
  end
end
