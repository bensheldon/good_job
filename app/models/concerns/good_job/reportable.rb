# frozen_string_literal: true

module GoodJob
  module Reportable
    # There are 3 buckets of non-overlapping statuses:
    #   1. The job will be executed
    #     - queued: The job will execute immediately when an execution thread becomes available.
    #     - scheduled: The job is scheduled to execute in the future.
    #     - retried: The job previously errored on execution and will be re-executed in the future.
    #   2. The job is being executed
    #     - running: the job is actively being executed by an execution thread
    #   3. The job has finished
    #     - succeeded: The job executed successfully
    #     - discarded: The job previously errored on execution and will not be re-executed in the future.
    #
    # @return [Symbol]
    def status
      if finished_at.present?
        if error.present?
          :discarded
        else
          :succeeded
        end
      elsif performed_at.present?
        :running
      elsif (scheduled_at || created_at) <= DateTime.current
        :queued
      elsif error.present?
        :retried
      else
        :scheduled
      end
    end

    # The last relevant timestamp for this job
    def last_status_at
      finished_at || performed_at || scheduled_at || created_at
    end
  end
end
