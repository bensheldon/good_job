# frozen_string_literal: true

module GoodJob
  # Shared methods for filtering Execution/Job records from the +good_jobs+ table.
  module ErrorEvents
    extend ActiveSupport::Concern

    included do
      error_event_enum = {
        interrupted: 0,
        unhandled: 1,
        handled: 2,
        retried: 3,
        retry_stopped: 4,
        discarded: 5,
      }
      if Gem::Version.new(Rails.version) >= Gem::Version.new('7.1.0.a')
        enum :error_event, error_event_enum, validate: { allow_nil: true }, scopes: false
      else
        enum error_event: error_event_enum, _scopes: false
      end
    end
  end
end
