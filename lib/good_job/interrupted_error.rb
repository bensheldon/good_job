# frozen_string_literal: true

module GoodJob
  # Represents a previous execution that was interrupted by a SIGKILL or power failure.
  # Used only to format the error string stored in the database for the interrupted execution record.
  # This error is never raised and cannot be rescued; use +GoodJob::InterruptError+ for that.
  class InterruptedError < StandardError
  end
end
