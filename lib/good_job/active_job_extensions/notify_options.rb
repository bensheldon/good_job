# frozen_string_literal: true

module GoodJob
  module ActiveJobExtensions
    # Allows configuring whether GoodJob should emit a NOTIFY event when a job is enqueued.
    # Configuration will apply either globally to the Job Class, or individually to jobs
    # on initial enqueue and subsequent retries.
    #
    # @example
    #   # Include the concern to your job class:
    #   class MyJob < ApplicationJob
    #     include GoodJob::ActiveJobExtensions::Notify
    #     self.good_job_notify = false
    #   end
    #
    #   # Or, configure jobs individually to not notify:
    #   MyJob.set(good_job_notify: false).perform_later
    #
    module NotifyOptions
      extend ActiveSupport::Concern

      module Prepends
        def enqueue(options = {})
          self.good_job_notify = options[:good_job_notify] if options.key?(:good_job_notify)
          super
        end

        def serialize
          super.tap do |job_data|
            # Only serialize the value if present to reduce the size of the serialized job
            job_data["good_job_notify"] = good_job_notify unless good_job_notify.nil?
          end
        end

        def deserialize(job_data)
          super
          self.good_job_notify = job_data["good_job_notify"]
        end
      end

      included do
        prepend Prepends
        class_attribute :good_job_notify, instance_accessor: false, instance_predicate: false, default: nil
        attr_accessor :good_job_notify
      end
    end
  end
end
