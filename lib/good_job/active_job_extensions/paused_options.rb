# frozen_string_literal: true

module GoodJob
  module ActiveJobExtensions
    # Allows configuring whether the job should start 'paused' when a job is enqueued.
    # Configuration will apply either globally to the Job Class, or individually to jobs
    # on initial enqueue and subsequent retries.
    #
    # @example
    #   # Include the concern to your job class:
    #   class MyJob < ApplicationJob
    #     include GoodJob::ActiveJobExtensions::PausedOptions
    #     self.good_job_paused = true
    #   end
    #
    #   # Or, configure jobs individually to not notify:
    #   MyJob.set(good_job_paused: true).perform_later

    # TODO: should this be enabled globally/by default? (the 'do not run if nil' logic will always be active)
    # TODO: consider renaming to 'Pauseable'

    module PausedOptions
      extend ActiveSupport::Concern

      module Prepends
        def enqueue(options = {})
          self.good_job_paused = options[:good_job_paused] if options.key?(:good_job_paused)
          super
        end

        def serialize
          super.tap do |job_data|
            # Only serialize the value if present to reduce the size of the serialized job
            job_data["good_job_paused"] = good_job_paused unless good_job_paused.nil?
          end
        end

        def deserialize(job_data)
          super
          self.good_job_paused = job_data["good_job_paused"]
        end
      end

      included do
        prepend Prepends
        class_attribute :good_job_paused, instance_accessor: false, instance_predicate: false, default: nil
        attr_accessor :good_job_paused
      end
    end
  end
end
