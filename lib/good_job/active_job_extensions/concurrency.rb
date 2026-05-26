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
        attr_reader :label, :total_limit, :enqueue_limit, :perform_limit, :enqueue_throttle, :perform_throttle

        def initialize(label: nil, key: GoodJob::NONE, total_limit: nil, enqueue_limit: nil, perform_limit: nil, enqueue_throttle: nil, perform_throttle: nil)
          @label = label
          @key = key
          @total_limit = total_limit
          @enqueue_limit = enqueue_limit
          @perform_limit = perform_limit
          @enqueue_throttle = enqueue_throttle
          @perform_throttle = perform_throttle
        end

        def key
          @key.equal?(GoodJob::NONE) ? nil : @key
        end

        def evaluate(job, stage)
          resolved_key = resolve_key(job)
          resolved_label = resolve_label(job)
          return nil if resolved_key.blank? && resolved_label.blank?

          if stage == :enqueue
            enqueue_limit = resolve_limit(job, @enqueue_limit) || resolve_limit(job, @total_limit)
            enqueue_throttle = resolve_throttle(job, @enqueue_throttle)
            return nil unless enqueue_limit || enqueue_throttle

            check_enqueue(enqueue_limit, enqueue_throttle, job, resolved_key, resolved_label, enqueue_limit_flag: @enqueue_limit.present?)
          elsif stage == :perform
            perform_limit = resolve_limit(job, @perform_limit) || resolve_limit(job, @total_limit)
            perform_throttle = resolve_throttle(job, @perform_throttle)
            return nil unless perform_limit || perform_throttle

            check_perform(perform_limit, perform_throttle, job, resolved_key, resolved_label)
          end
        end

        private

        def key_explicit?
          !@key.equal?(GoodJob::NONE)
        end

        def resolve_key(job)
          if key.blank?
            "label:#{resolve_label(job)}"
          else
            key_value = @key.respond_to?(:call) ? job.instance_exec(&@key) : @key
            raise TypeError, "Concurrency key must be a String; was a #{key_value.class}" if key_value.present? && VALID_TYPES.none? { |type| key_value.is_a?(type) }

            key_value
          end
        end

        def resolve_label(job)
          return if @label.blank?

          @label.respond_to?(:call) ? job.instance_exec(&@label) : @label
        end

        def resolve_limit(job, value)
          return nil if value.nil?

          value = job.instance_exec(&value) if value.respond_to?(:call)
          value = nil unless value.present? && (0...Float::INFINITY).cover?(value)
          value
        end

        def resolve_throttle(job, value)
          return nil if value.nil?

          value = job.instance_exec(&value) if value.respond_to?(:call)
          value = nil unless value.present? && value.is_a?(Array) && value.size == 2
          value
        end

        def query_scope(label, key)
          if label.present?
            GoodJob::Job.labeled(label)
          elsif key_explicit? && key.present?
            GoodJob::Job.where(concurrency_key: key)
          else
            GoodJob::Job.all
          end
        end

        def check_enqueue(limit, throttle, job, key, label, enqueue_limit_flag: false)
          return nil if label.present? && job.good_job_labels.exclude?(label)

          query_scope = query_scope(label, key)
          exceeded = nil

          GoodJob::Job.transaction(requires_new: true, joinable: false) do
            GoodJob::Job.advisory_lock_key(key, function: "pg_advisory_xact_lock") do
              if limit
                # Use advisory_unlocked + where(locked_by_id: nil) when enqueue_limit_flag is set
                # (legacy behavior), to exclude jobs currently claimed/performing from the count.
                # advisory_unlocked handles :advisory strategy; locked_by_id handles :skiplocked/:hybrid.
                enqueue_concurrency = if enqueue_limit_flag
                                        query_scope.unfinished.advisory_unlocked.where(locked_by_id: nil).count
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
            rules = [Rule.new(**job.class.good_job_concurrency_config.merge(key: legacy_key)), *rules] if legacy_key.present?
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
            rules = [Rule.new(**job.class.good_job_concurrency_config.merge(key: legacy_key)), *rules] if legacy_key.present?
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
        def good_job_control_concurrency_with(
          total_limit: NONE,
          enqueue_limit: NONE,
          perform_limit: NONE,
          enqueue_throttle: NONE,
          perform_throttle: NONE,
          key: NONE
        )
          self.good_job_concurrency_config = {
            total_limit: total_limit,
            enqueue_limit: enqueue_limit,
            perform_limit: perform_limit,
            enqueue_throttle: enqueue_throttle,
            perform_throttle: perform_throttle,
            key: key,
          }.reject { |_key, value| value.equal?(NONE) }
        end

        # Define a concurrency rule. Rules are appended to the class-level
        # `good_job_concurrency_rules` array. Each rule uses keyword arguments that may
        # include keys such as :label, :key (optional lock key), and
        # stage-specific settings like :enqueue_limit, :enqueue_throttle,
        # :perform_limit, :perform_throttle, and :total_limit.
        def good_job_concurrency_rule(
          label: NONE,
          key: NONE,
          total_limit: NONE,
          enqueue_limit: NONE,
          perform_limit: NONE,
          enqueue_throttle: NONE,
          perform_throttle: NONE
        )
          rule = {
            label: label,
            key: key,
            total_limit: total_limit,
            enqueue_limit: enqueue_limit,
            perform_limit: perform_limit,
            enqueue_throttle: enqueue_throttle,
            perform_throttle: perform_throttle,
          }.reject { |_key, value| value.equal?(NONE) }

          self.good_job_concurrency_rules = Array(good_job_concurrency_rules) + [Rule.new(**rule)]
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
