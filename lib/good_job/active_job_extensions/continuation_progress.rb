# frozen_string_literal: true

module GoodJob
  module ActiveJobExtensions
    # Allows overriding, per job class, the minimum number of seconds between periodic
    # writes of an Active Job continuation's progress. When +nil+ (the default),
    # {GoodJob::Configuration#continuation_progress_interval} is used.
    #
    # @example
    #   class MyJob < ApplicationJob
    #     include ActiveJob::Continuable
    #     include GoodJob::ActiveJobExtensions::ContinuationProgress
    #
    #     # Write progress at most every 30 seconds
    #     self.good_job_continuation_progress_interval = 30.seconds
    #     # Or, only write progress on a graceful interruption
    #     self.good_job_continuation_progress_interval = false
    #   end
    #
    module ContinuationProgress
      extend ActiveSupport::Concern

      included do
        class_attribute :good_job_continuation_progress_interval, instance_accessor: false, instance_predicate: false, default: nil
      end
    end
  end
end
