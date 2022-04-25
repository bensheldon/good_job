# frozen_string_literal: true
module GoodJob
  # Base ActiveRecord class that all GoodJob models inherit from.
  # Parent class can be configured with +GoodJob.active_record_parent_class+.
  # @!parse
  #   class BaseRecord < ActiveRecord::Base; end
  class BaseRecord < Object.const_get(GoodJob.active_record_parent_class)
    self.abstract_class = true

    def self.migration_pending_warning!
      ActiveSupport::Deprecation.warn(<<~DEPRECATION)
        GoodJob has pending database migrations. To create the migration files, run:
            rails generate good_job:update
        To apply the migration files, run:
            rails db:migrate
      DEPRECATION
      nil
    end

    # Time between when this job was expected to run and when it started running
    def latency
      now = Time.zone.now
      expected_start = scheduled_at || created_at
      actual_start = performed_at || now

      actual_start - expected_start unless expected_start >= now
    end

    # Time between when this job started and finished
    def runtime
      (finished_at || Time.zone.now) - performed_at if performed_at
    end
  end
end
