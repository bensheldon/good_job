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

      ThrottleExceededError = Class.new(ConcurrencyExceededError)

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

          perform_throttle = job.class.good_job_concurrency_config[:perform_throttle]
          perform_throttle = instance_exec(&perform_throttle) if perform_throttle.respond_to?(:call)
          perform_throttle = nil unless GoodJob::DiscreteExecution.migrated? && perform_throttle.present? && perform_throttle.is_a?(Array) && perform_throttle.size == 2

          limit = perform_limit || total_limit
          throttle = perform_throttle
          next unless limit || throttle

          key = job.good_job_concurrency_key
          next if key.blank?

          if CurrentThread.execution.blank? || CurrentThread.execution.active_job_id != job_id
            logger.debug("Ignoring concurrency limits because the job is executed with `perform_now`.")
            next
          end

          GoodJob::Execution.advisory_lock_key(key, function: "pg_advisory_lock") do
            if limit
              allowed_active_job_ids = GoodJob::Execution.unfinished.where(concurrency_key: key)
                                                         .advisory_locked
                                                         .order(Arel.sql("COALESCE(performed_at, scheduled_at, created_at) ASC"))
                                                         .limit(limit).pluck(:active_job_id)
              # The current job has already been locked and will appear in the previous query
              raise GoodJob::ActiveJobExtensions::Concurrency::ConcurrencyExceededError unless allowed_active_job_ids.include?(job.job_id)
            end

            if throttle
              throttle_limit = throttle[0]
              throttle_period = throttle[1]

              query = DiscreteExecution.joins(:job)
                                       .where(GoodJob::Job.table_name => { concurrency_key: key })
                                       .where(DiscreteExecution.arel_table[:created_at].gt(DiscreteExecution.bind_value('created_at', throttle_period.ago, ActiveRecord::Type::DateTime)))
              allowed_active_job_ids = query.where(error: nil).or(query.where.not(error: "GoodJob::ActiveJobExtensions::Concurrency::ThrottleExceededError: GoodJob::ActiveJobExtensions::Concurrency::ThrottleExceededError"))
                                            .order(created_at: :asc)
                                            .limit(throttle_limit)
                                            .pluck(:active_job_id)

              raise ThrottleExceededError unless allowed_active_job_ids.include?(job.job_id)
            end
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
        return _good_job_default_concurrency_key unless self.class.good_job_concurrency_config.key?(:key)

        key = self.class.good_job_concurrency_config[:key]
        return if key.blank?

        key = instance_exec(&key) if key.respond_to?(:call)
        raise TypeError, "Concurrency key must be a String; was a #{key.class}" unless VALID_TYPES.any? { |type| key.is_a?(type) }

        key
      end

      # Generates the default concurrency key when the configuration doesn't provide one
      # @return [String] concurrency key
      def _good_job_default_concurrency_key
        self.class.name.to_s
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

        enqueue_throttle = job.class.good_job_concurrency_config[:enqueue_throttle]
        enqueue_throttle = instance_exec(&enqueue_throttle) if enqueue_throttle.respond_to?(:call)
        enqueue_throttle = nil unless enqueue_throttle.present? && enqueue_throttle.is_a?(Array) && enqueue_throttle.size == 2

        limit = enqueue_limit || total_limit
        throttle = enqueue_throttle
        return on_enqueue&.call unless limit || throttle

        GoodJob::Execution.advisory_lock_key(key, function: "pg_advisory_lock") do
          if limit
            enqueue_concurrency = if enqueue_limit
                                    GoodJob::Execution.where(concurrency_key: key).unfinished.advisory_unlocked.count
                                  else
                                    GoodJob::Execution.where(concurrency_key: key).unfinished.count
                                  end

            # The job has not yet been enqueued, so check if adding it will go over the limit
            if (enqueue_concurrency + 1) > limit
              logger.info "Aborted enqueue of #{job.class.name} (Job ID: #{job.job_id}) because the concurrency key '#{key}' has reached its enqueue limit of #{limit} #{'job'.pluralize(limit)}"
              on_abort&.call
              break
            end
          end

          if throttle
            throttle_limit = throttle[0]
            throttle_period = throttle[1]
            enqueued_within_period = GoodJob::Job.where(concurrency_key: key)
                                                 .where(GoodJob::Job.arel_table[:created_at].gt(throttle_period.ago))
                                                 .count

            if (enqueued_within_period + 1) > throttle_limit
              logger.info "Aborted enqueue of #{job.class.name} (Job ID: #{job.job_id}) because the concurrency key '#{key}' has reached its throttle limit of #{limit} #{'job'.pluralize(limit)}"
              on_abort&.call
              break
            end
          end

          on_enqueue&.call
        end
      end
    end
  end
end
