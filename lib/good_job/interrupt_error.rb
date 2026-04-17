# frozen_string_literal: true

module GoodJob
  # Exception raised within a job when it is retried after being interrupted by a SIGKILL or power failure.
  # Include +GoodJob::ActiveJobExtensions::InterruptErrors+ in your job class to enable this behavior,
  # then use +retry_on+ or +discard_on+ to control how interrupted jobs are handled.
  # The error stored in the database for the interrupted execution record itself uses +GoodJob::InterruptedError+.
  class InterruptError < StandardError
  end
end
