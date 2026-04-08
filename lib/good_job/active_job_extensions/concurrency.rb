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

      class Rule
        def initialize(config)
          @config = config
        end

        def evaluate(job, stage)
          key = key(job)
          label = label(job)
          return nil if key.blank? && label.blank?

          if stage == :enqueue
            enqueue_limit = limit(job, :enqueue_limit) || limit(job, :total_limit)
            enqueue_throttle = throttle(job, :enqueue_throttle)
            return nil unless enqueue_limit || enqueue_throttle

            check_enqueue(enqueue_limit, enqueue_throttle, job, key, label, enqueue_limit_flag: @config[:enqueue_limit].present?)
          elsif stage == :perform
            perform_limit = limit(job, :perform_limit) || limit(job, :total_limit)
            perform_throttle = throttle(job, :perform_throttle)
            return nil unless perform_limit || perform_throttle

            check_perform(perform_limit, perform_throttle, job, key, label)
          end
        end

        def key(job)
          key_spec = @config[:key]
          if key_spec.blank?
            "label:#{label(job)}"
          else
            key_value = key_spec.respond_to?(:call) ? job.instance_exec(&key_spec) : key_spec
            raise TypeError, "Concurrency key must be a String; was a #{key_value.class}" if key_value.present? && VALID_TYPES.none? { |type| key_value.is_a?(type) }

            key_value
          end
        end

        def label(job)
          label_spec = @config[:label]

          return if label_spec.blank?

          label_spec.respond_to?(:call) ? job.instance_exec(&label_spec) : label_spec
        end

        def limit(job, limit_name)
          value = @config[limit_name]
          return nil if value.nil?

          value = job.instance_exec(&value) if value.respond_to?(:call)
          value = nil unless value.present? && (0...Float::INFINITY).cover?(value)
          value
        end

        def throttle(job, throttle_name)
          value = @config[throttle_name]
          return nil if value.nil?

          value = job.instance_exec(&value) if value.respond_to?(:call)
          value = nil unless value.present? && value.is_a?(Array) && value.size == 2
          value
        end

        private

        def query_scope(label, key)
          if label.present?
            GoodJob::Job.labeled(label)
          elsif @config.key?(:key) && key.present?
            GoodJob::Job.where(concurrency_key: key)
          else
            GoodJob::Job
          end
        end

        def check_enqueue(limit, throttle, job, key, label, enqueue_limit_flag: false)
          return nil if label.present? && job.good_job_labels.exclude?(label)

          query_scope = query_scope(label, key)
          exceeded = nil

          GoodJob::Job.transaction(requires_new: true, joinable: false) do
            GoodJob::Job.advisory_lock_key(key, function: "pg_advisory_xact_lock") do
              if limit
                # Use where(performed_at: nil) when enqueue_limit_flag is set (legacy behavior),
                # to exclude jobs currently being performed from the enqueue limit count.
                enqueue_concurrency = if enqueue_limit_flag
                                        query_scope.unfinished.where(performed_at: nil).count
                                      else
                                        query_scope.unfinished.count
                                      end

                if (enqueue_concurrency + 1) > limit
                  job.logger.info "Aborted enqueue of #{job.class.name} (Job ID: #{job.job_id}) because the concurrency key '#{key}' has reached its enqueue limit of #{limit} #{'job'.pluralize(limit)}"
                  exceeded = :limit
                  next
                end
              end

              if throttle
                throttle_limit = throttle[0]
                throttle_period = throttle[1]
                enqueued_within_period = query_scope
                                         .where(GoodJob::Job.arel_table[:created_at].gt(throttle_period.ago))
                                         .count

                if (enqueued_within_period + 1) > throttle_limit
                  job.logger.info "Aborted enqueue of #{job.class.name} (Job ID: #{job.job_id}) because the concurrency key '#{key}' has reached its throttle limit of #{throttle_limit} #{'job'.pluralize(throttle_limit)}"
                  exceeded = :throttle
                  next
                end
              end
            end

            # Rollback the transaction because it's potentially less expensive than committing it
            # even though nothing has been altered in the transaction.
            raise ActiveRecord::Rollback
          end

          exceeded
        end

        def check_perform(limit, throttle, job, key, label)
          return nil if label.present? && job.good_job_labels.exclude?(label)

          query_scope = query_scope(label, key)
          exceeded = nil

          GoodJob::Job.transaction(requires_new: true, joinable: false) do
            GoodJob::Job.advisory_lock_key(key, function: "pg_advisory_xact_lock") do
              if limit
                allowed_active_job_ids = query_scope.running
                                                    .order(Arel.sql("COALESCE(performed_at, scheduled_at, created_at) ASC"))
                                                    .limit(limit).pluck(:active_job_id)
                # The current job has already been locked and will appear in the previous query
                unless allowed_active_job_ids.include?(job.job_id)
                  exceeded = :limit
                  next
                end
              end

              if throttle
                throttle_limit = throttle[0]
                throttle_period = throttle[1]

                execution_base = Execution.joins(:job).merge(query_scope)

                query = execution_base
                        .where(Execution.arel_table[:created_at].gt(Execution.bind_value('created_at', throttle_period.ago, ActiveRecord::Type::DateTime)))

                allowed_active_job_ids = query.where(error: nil).or(query.where.not(error: "GoodJob::ActiveJobExtensions::Concurrency::ThrottleExceededError: GoodJob::ActiveJobExtensions::Concurrency::ThrottleExceededError"))
                                              .order(created_at: :asc)
                                              .limit(throttle_limit)
                                              .pluck(:active_job_id)

                unless allowed_active_job_ids.include?(job.job_id)
                  exceeded = :throttle
                  next
                end
              end
            end

            # Rollback the transaction because it's potentially less expensive than committing it
            # even though nothing has been altered in the transaction.
            raise ActiveRecord::Rollback
          end

          exceeded
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
        include GoodJob::ActiveJobExtensions::Labels

        class_attribute :good_job_concurrency_config, instance_accessor: false, default: {}
        class_attribute :good_job_concurrency_rules, instance_accessor: false, default: []
        attr_writer :good_job_concurrency_key

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

        before_enqueue do |job|
          # Don't attempt to enforce concurrency limits with other queue adapters.
          next unless job.class.queue_adapter.is_a?(GoodJob::Adapter)

          # Always allow jobs to be retried because the current job's execution will complete momentarily
          next if CurrentThread.active_job_id == job.job_id

          rules = job.class.good_job_concurrency_rules

          # Only generate the concurrency key on the initial enqueue in case it is dynamic
          if job.class.good_job_concurrency_config.present?
            job.good_job_concurrency_key ||= job._good_job_concurrency_key
            legacy_key = job.good_job_concurrency_key
            rules = [Rule.new(job.class.good_job_concurrency_config.merge(key: legacy_key)), *rules] if legacy_key.present?
          end

          exceeded = nil
          rules.each do |rule|
            exceeded = rule.evaluate(job, :enqueue)
            break if exceeded
          end

          throw :abort if exceeded
        end

        before_perform do |job|
          # Don't attempt to enforce concurrency limits with other queue adapters.
          next unless job.class.queue_adapter.is_a?(GoodJob::Adapter)

          if CurrentThread.job.blank? || CurrentThread.job.active_job_id != job_id
            logger.debug("Ignoring concurrency limits because the job is executed with `perform_now`.")
            next
          end

          rules = job.class.good_job_concurrency_rules

          if job.class.good_job_concurrency_config.present?
            legacy_key = job.good_job_concurrency_key
            rules = [Rule.new(job.class.good_job_concurrency_config.merge(key: legacy_key)), *rules] if legacy_key.present?
          end

          exceeded = nil
          rules.each do |rule|
            exceeded = rule.evaluate(job, :perform)
            break if exceeded
          end

          if exceeded == :limit
            raise GoodJob::ActiveJobExtensions::Concurrency::ConcurrencyExceededError
          elsif exceeded == :throttle
            raise GoodJob::ActiveJobExtensions::Concurrency::ThrottleExceededError
          end
        end
      end

      class_methods do
        def good_job_control_concurrency_with(config)
          self.good_job_concurrency_config = config
        end

        # Define a concurrency rule. Rules are appended to the class-level
        # `good_job_concurrency_rules` array. Each rule is a Hash that may
        # include keys such as :label, :key (optional lock key), and
        # stage-specific settings like :enqueue_limit, :enqueue_throttle,
        # :perform_limit, :perform_throttle, and :total_limit/:total_throttle.
        def good_job_concurrency_rule(rule)
          self.good_job_concurrency_rules = Array(good_job_concurrency_rules) + [Rule.new(rule)]
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
    end
  end
end
