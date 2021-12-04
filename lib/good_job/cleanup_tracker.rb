# frozen_string_literal: true
module GoodJob # :nodoc:
  # Tracks thresholds for cleaning up old jobs.
  class CleanupTracker
    attr_accessor :cleanup_interval_seconds,
                  :cleanup_interval_jobs,
                  :job_count,
                  :last_at

    def initialize(cleanup_interval_seconds: nil, cleanup_interval_jobs: nil)
      self.cleanup_interval_seconds = cleanup_interval_seconds
      self.cleanup_interval_jobs = cleanup_interval_jobs

      reset
    end

    # Increments job count.
    # @return [void]
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
