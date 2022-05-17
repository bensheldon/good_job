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
  end
end
