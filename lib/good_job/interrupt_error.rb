# frozen_string_literal: true

module GoodJob
  # Exception raised when a job is interrupted by a SIGKILL or power failure.
  class InterruptError < StandardError
  end
end
