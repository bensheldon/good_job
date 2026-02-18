# frozen_string_literal: true

module GoodJob
  # Shared methods for filtering Execution/Job records from the +good_jobs+ table.
  module ErrorEvents
    extend ActiveSupport::Concern

    INTERRUPTED = :interrupted
    UNHANDLED = :unhandled
    HANDLED = :handled
    RETRIED = :retried
    RETRY_STOPPED = :retry_stopped
    DISCARDED = :discarded

    included do
      error_event_enum = {
        INTERRUPTED => 0,
        UNHANDLED => 1,
        HANDLED => 2,
        RETRIED => 3,
        RETRY_STOPPED => 4,
        DISCARDED => 5,
      }
      if Gem::Version.new(Rails.version) >= Gem::Version.new('7.1.0.a')
        enum :error_event, error_event_enum, validate: { allow_nil: true }, scopes: false
      else
        enum error_event: error_event_enum, _scopes: false
      end
    end
  end
end
