# frozen_string_literal: true

module GoodJob
  module ActiveJobExtensions
    # Allows configuring whether the job should start 'paused' when a job is enqueued.
    # Configuration will apply either globally to the Job Class, or individually to jobs
    # on initial enqueue and subsequent retries.
    #
    # @example
    #   class MyJob < ApplicationJob
    #     self.good_job_paused = true
    #   end
    #
    #   # Or, configure jobs individually to not notify:
    #   MyJob.set(good_job_paused: true).perform_later
    #
    # See also - GoodJob:Batch#new's `paused` option

    module Pauseable
      extend ActiveSupport::Concern

      module Prepends
        def enqueue(options = {})
          self.good_job_paused = options[:good_job_paused] if options.key?(:good_job_paused)
          super
        end

        # good_job_paused is intentionally excluded from the serialized params so we fully rely on the scheduled_at value once the job is enqueued
        # def serialize
        #   super.tap do |job_data|
        #     # job_data["good_job_paused"] = good_job_paused unless good_job_paused.nil?
        #   end
        # end

        # def deserialize(job_data)
        #   super
        #   self.good_job_paused = job_data["good_job_paused"]
        # end
      end

      included do
        prepend Prepends
        class_attribute :good_job_paused, instance_accessor: false, instance_predicate: false, default: nil
        attr_accessor :good_job_paused
      end
    end
  end
end

# Jobs can be paused through batches which rely on good_job_paused being available, so this must be included globally
ActiveJob::Base.include GoodJob::ActiveJobExtensions::Pauseable
