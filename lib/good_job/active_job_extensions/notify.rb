# frozen_string_literal: true
module GoodJob
  module ActiveJobExtensions
    # Allows configuring whether GoodJob should emit a NOTIFY event when a job is enqueued.
    #
    # @example
    #   # Include the concern to your job class:
    #   class MyJob < ApplicationJob
    #     include GoodJob::ActiveJobExtensions::Notify
    #   end
    #
    #   # Configure the job to not notify:
    #   MyJob.set(good_job_notify: false).perform_later
    #
    module Notify
      extend ActiveSupport::Concern

      module Prepends
        def enqueue(options = {})
          self.good_job_notify = options.fetch(:good_job_notify, true)
          super
        end
      end

      included do
        prepend Prepends
        attr_accessor :good_job_notify
      end
    end
  end
end
