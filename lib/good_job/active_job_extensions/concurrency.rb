# frozen_string_literal: true
module GoodJob
  module ActiveJobExtensions
    module Concurrency
      extend ActiveSupport::Concern

      class ConcurrencyExceededError < StandardError
        def backtrace
          [] # suppress backtrace
        end
      end

      included do
        class_attribute :good_job_concurrency_config, instance_accessor: false, default: {}

        around_enqueue do |job, block|
          # Don't attempt to enforce concurrency limits with other queue adapters.
          next(block.call) unless job.class.queue_adapter.is_a?(GoodJob::Adapter)

          # Always allow jobs to be retried because the current job's execution will complete momentarily
          next(block.call) if CurrentThread.active_job_id == job.job_id

          enqueue_limit = job.class.good_job_concurrency_config[:enqueue_limit]
          total_limit = job.class.good_job_concurrency_config[:total_limit]

          has_limit = (enqueue_limit.present? && (0...Float::INFINITY).cover?(enqueue_limit)) ||
                      (total_limit.present? && (0...Float::INFINITY).cover?(total_limit))
          next(block.call) unless has_limit

          key = job.good_job_concurrency_key
          next(block.call) if key.blank?

          GoodJob::Execution.with_advisory_lock(key: key, function: "pg_advisory_lock") do
            enqueue_concurrency = if enqueue_limit
                                    GoodJob::Execution.where(concurrency_key: key).unfinished.advisory_unlocked.count
                                  else
                                    GoodJob::Execution.where(concurrency_key: key).unfinished.count
                                  end

            # The job has not yet been enqueued, so check if adding it will go over the limit
            block.call unless enqueue_concurrency + 1 > (enqueue_limit || total_limit)
          end
        end

        retry_on(
          GoodJob::ActiveJobExtensions::Concurrency::ConcurrencyExceededError,
          attempts: Float::INFINITY,
          wait: :exponentially_longer
        )

        before_perform do |job|
          # Don't attempt to enforce concurrency limits with other queue adapters.
          next unless job.class.queue_adapter.is_a?(GoodJob::Adapter)

          perform_limit = job.class.good_job_concurrency_config[:perform_limit] ||
                          job.class.good_job_concurrency_config[:total_limit]

          has_limit = perform_limit.present? && (0...Float::INFINITY).cover?(perform_limit)
          next unless has_limit

          key = job.good_job_concurrency_key
          next if key.blank?

          GoodJob::Execution.with_advisory_lock(key: key, function: "pg_advisory_lock") do
            allowed_active_job_ids = GoodJob::Execution.where(concurrency_key: key).advisory_locked.order(Arel.sql("COALESCE(performed_at, scheduled_at, created_at) ASC")).limit(perform_limit).pluck(:active_job_id)
            # The current job has already been locked and will appear in the previous query
            raise GoodJob::ActiveJobExtensions::Concurrency::ConcurrencyExceededError unless allowed_active_job_ids.include? job.job_id
          end
        end
      end

      class_methods do
        def good_job_control_concurrency_with(config)
          self.good_job_concurrency_config = config
        end
      end

      def good_job_concurrency_key
        key = self.class.good_job_concurrency_config[:key]
        return if key.blank?

        if key.respond_to? :call
          instance_exec(&key)
        else
          key
        end
      end
    end
  end
end
