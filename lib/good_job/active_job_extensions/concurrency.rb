# frozen_string_literal: true

module GoodJob
  module ActiveJobExtensions
    module Concurrency
      extend ActiveSupport::Concern

      VALID_TYPES = [String, Symbol, Numeric, Date, Time, TrueClass, FalseClass, NilClass].freeze

      class ConcurrencyExceededError < StandardError
        def backtrace
          [] # suppress backtrace
        end
      end

      module Prepends
        def deserialize(job_data)
          super
          self.good_job_concurrency_key = job_data['good_job_concurrency_key']
        end
      end

      included do
        prepend Prepends

        class_attribute :good_job_concurrency_config, instance_accessor: false, default: {}
        attr_writer :good_job_concurrency_key

        if ActiveJob.gem_version >= Gem::Version.new("6.1.0")
          before_enqueue do |job|
            good_job_enqueue_concurrency_check(job, on_abort: -> { throw(:abort) }, on_enqueue: nil)
          end
        else
          around_enqueue do |job, block|
            good_job_enqueue_concurrency_check(job, on_abort: nil, on_enqueue: block)
          end
        end

        wait_key = if ActiveJob.gem_version >= Gem::Version.new("7.1.0.a")
                     :polynomially_longer
                   else
                     :exponentially_longer
                   end

        retry_on(
          GoodJob::ActiveJobExtensions::Concurrency::ConcurrencyExceededError,
          attempts: Float::INFINITY,
          wait: wait_key
        )

        before_perform do |job|
          # Don't attempt to enforce concurrency limits with other queue adapters.
          next unless job.class.queue_adapter.is_a?(GoodJob::Adapter)

          perform_limit = job.class.good_job_concurrency_config[:perform_limit]
          perform_limit = instance_exec(&perform_limit) if perform_limit.respond_to?(:call)
          perform_limit = nil unless perform_limit.present? && (0...Float::INFINITY).cover?(perform_limit)

          unless perform_limit
            total_limit = job.class.good_job_concurrency_config[:total_limit]
            total_limit = instance_exec(&total_limit) if total_limit.respond_to?(:call)
            total_limit = nil unless total_limit.present? && (0...Float::INFINITY).cover?(total_limit)
          end

          limit = perform_limit || total_limit
          next unless limit

          key = job.good_job_concurrency_key
          next if key.blank?

          if CurrentThread.execution.blank?
            logger.debug("Ignoring concurrency limits because the job is executed with `perform_now`.")
            next
          end

          GoodJob::Execution.advisory_lock_key(key, function: "pg_advisory_lock") do
            allowed_active_job_ids = GoodJob::Execution.unfinished.where(concurrency_key: key).advisory_locked.order(Arel.sql("COALESCE(performed_at, scheduled_at, created_at) ASC")).limit(limit).pluck(:active_job_id)
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

      # Existing or dynamically generated concurrency key
      # @return [Object] concurrency key
      def good_job_concurrency_key
        @good_job_concurrency_key || _good_job_concurrency_key
      end

      # Generates the concurrency key from the configuration
      # @return [Object] concurrency key
      def _good_job_concurrency_key
        key = self.class.good_job_concurrency_config[:key]
        return if key.blank?

        key = instance_exec(&key) if key.respond_to?(:call)
        raise TypeError, "Concurrency key must be a String; was a #{key.class}" unless VALID_TYPES.any? { |type| key.is_a?(type) }

        key
      end

      private

      def good_job_enqueue_concurrency_check(job, on_abort:, on_enqueue:)
        # Don't attempt to enforce concurrency limits with other queue adapters.
        return on_enqueue&.call unless job.class.queue_adapter.is_a?(GoodJob::Adapter)

        # Always allow jobs to be retried because the current job's execution will complete momentarily
        return on_enqueue&.call if CurrentThread.active_job_id == job.job_id

        # Only generate the concurrency key on the initial enqueue in case it is dynamic
        job.good_job_concurrency_key ||= job._good_job_concurrency_key
        key = job.good_job_concurrency_key
        return on_enqueue&.call if key.blank?

        enqueue_limit = job.class.good_job_concurrency_config[:enqueue_limit]
        enqueue_limit = instance_exec(&enqueue_limit) if enqueue_limit.respond_to?(:call)
        enqueue_limit = nil unless enqueue_limit.present? && (0...Float::INFINITY).cover?(enqueue_limit)

        unless enqueue_limit
          total_limit = job.class.good_job_concurrency_config[:total_limit]
          total_limit = instance_exec(&total_limit) if total_limit.respond_to?(:call)
          total_limit = nil unless total_limit.present? && (0...Float::INFINITY).cover?(total_limit)
        end

        limit = enqueue_limit || total_limit
        return on_enqueue&.call unless limit

        GoodJob::Execution.advisory_lock_key(key, function: "pg_advisory_lock") do
          enqueue_concurrency = if enqueue_limit
                                  GoodJob::Execution.where(concurrency_key: key).unfinished.advisory_unlocked.count
                                else
                                  GoodJob::Execution.where(concurrency_key: key).unfinished.count
                                end

          # The job has not yet been enqueued, so check if adding it will go over the limit
          if (enqueue_concurrency + 1) > limit
            logger.info "Aborted enqueue of #{job.class.name} (Job ID: #{job.job_id}) because the concurrency key '#{key}' has reached its limit of #{limit} #{'job'.pluralize(limit)}"
            on_abort&.call
          else
            on_enqueue&.call
          end
        end
      end
    end
  end
end
