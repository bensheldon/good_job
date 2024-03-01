# frozen_string_literal: true

module GoodJob
  module ActiveJobExtensions
    module Throttle
      extend ActiveSupport::Concern

      GoodJobThrottleExceededError = Class.new(GoodJob::ActiveJobExtensions::Concurrency::ConcurrencyExceededError)

      included do
        include GoodJob::ActiveJobExtensions::Concurrency

        class_attribute :throttle_enabled, default: false
        class_attribute :throttle_count, default: 2
        class_attribute :throttle_period, default: 1.minute
        class_attribute :throttle_key, default: -> { self.class.name }

        before_perform do |job|
          next unless job.class.throttle_enabled

          throttle_key = job.class.throttle_key.respond_to?(:call) ? job.class.throttle_key.call(job) : job.class.throttle_key
          throttle_count = job.class.throttle_count.respond_to?(:call) ? job.class.throttle_count.call(job) : job.class.throttle_count
          throttle_period = job.class.throttle_period.respond_to?(:call) ? job.class.throttle_period.call(job) : job.class.throttle_period

          GoodJob::Execution.advisory_lock_key("throttle_#{throttle_key}", function: "pg_advisory_lock") do
            allowed_active_job_ids = GoodJob::Job.where.not(error: GoodJobThrottleExceededError.to_s)
              .or(GoodJob::Job.where(error: nil))
              .where("performed_at > ?", throttle_period.ago)
              .where(job_class: job.class.to_s)
              .where(concurrency_key: throttle_key)
              .order(performed_at: :asc)
              .limit(throttle_count)
              .pluck(:active_job_id)

            job_allowed = allowed_active_job_ids.include?(job.job_id)
            within_threshold = allowed_active_job_ids.count < throttle_count

            raise GoodJobThrottleExceededError unless job_allowed || within_threshold
          end
        end
      end

      class_methods do
        def good_job_throttle_with(count: 1, period: 1.minute, key: ->(job) { job.class.name })
          self.throttle_enabled = true
          self.throttle_count = count
          self.throttle_period = period
          self.throttle_key = key
        end
      end
    end
  end
end