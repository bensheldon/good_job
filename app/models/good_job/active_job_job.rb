# frozen_string_literal: true
module GoodJob
  # @deprecated Use {GoodJob::Job} instead.
  class ActiveJobJob < Execution
    after_initialize do |_job|
      ActiveSupport::Deprecation.warn(
        "The `GoodJob::ActiveJobJob` class name is deprecated. Replace with `GoodJob::Job`."
      )
    end
  end
end
