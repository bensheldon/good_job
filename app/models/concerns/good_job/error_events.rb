# frozen_string_literal: true
module GoodJob
  # Shared methods for filtering Execution/Job records from the +good_jobs+ table.
  module ErrorEvents
    extend ActiveSupport::Concern

    ERROR_EVENTS = [
      ERROR_EVENT_INTERRUPTED = 'interrupted',
      ERROR_EVENT_UNHANDLED = 'unhandled',
      ERROR_EVENT_HANDLED = 'handled',
      ERROR_EVENT_RETRIED = 'retried',
      ERROR_EVENT_RETRY_STOPPED = 'retry_stopped',
      ERROR_EVENT_DISCARDED = 'discarded',
    ].freeze

    included do
      enum error_event: {
        ERROR_EVENT_INTERRUPTED => 0,
        ERROR_EVENT_UNHANDLED => 1,
        ERROR_EVENT_HANDLED => 2,
        ERROR_EVENT_RETRIED => 3,
        ERROR_EVENT_RETRY_STOPPED => 4,
        ERROR_EVENT_DISCARDED => 5,
      }.freeze, _prefix: :error_event
    end
  end
end
