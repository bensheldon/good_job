# frozen_string_literal: true
module GoodJob
  module Reportable
    # The last relevant timestamp for this execution
    def last_status_at
      finished_at || performed_at || scheduled_at || created_at
    end

    # Time between when this job was expected to run and when it started running
    def queue_latency
      now = Time.zone.now
      expected_start = scheduled_at || created_at
      actual_start = performed_at || finished_at || now

      actual_start - expected_start unless expected_start >= now
    end

    # Time between when this job started and finished
    def runtime_latency
      (finished_at || Time.zone.now) - performed_at if performed_at
    end
  end
end
