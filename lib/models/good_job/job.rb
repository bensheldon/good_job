# frozen_string_literal: true
module GoodJob
  # @deprecated Use {GoodJob::Execution} instead.
  class Job < Execution
    after_initialize do |_job|
      ActiveSupport::Deprecation.warn(
        "The `GoodJob::Job` class name is deprecated. Replace with `GoodJob::Execution`."
      )
    end
  end
end
