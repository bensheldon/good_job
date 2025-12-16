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

          # If rules are defined, evaluate each rule and use label-based queries
          if job.class.good_job_concurrency_rules.present?
            exceeded = nil
            # collect labels to persist
            labels_to_persist = []

            valid_enqueue_stages = [:enqueue, :total]

            job.class.good_job_concurrency_rules.each do |rule|
              rule_stage = rule[:stage].to_sym

              label_spec = rule[:label]
              label_value = label_spec.respond_to?(:call) ? job.instance_exec(&label_spec) : label_spec
              next if label_value.blank?

              limit = job._resolve_limit(rule[:limit])
              throttle = job._resolve_throttle(rule[:throttle])
              next unless limit || throttle

              limit_label = "concurrency:#{rule_stage}:limit:#{label_value}"
              throttle_label = "concurrency:#{rule_stage}:throttle:#{label_value}"

              labels_to_persist << limit_label if limit
              labels_to_persist << throttle_label if throttle

              # Enqueue checks apply for :enqueue and :total rules
              next unless valid_enqueue_stages.include?(rule_stage)

              enqueue_limit_flag = rule_stage == :enqueue && limit.present?
              exceeded = job._check_enqueue(limit, throttle, limit_label: limit_label, throttle_label: throttle_label, enqueue_limit_flag: enqueue_limit_flag)

              break if exceeded
            end

            # Save the labels to the job record
            job.good_job_labels = Array(job.good_job_labels) | labels_to_persist if labels_to_persist.any?
          else
            # Support for legacy concurrency configuration
            # Only generate the concurrency key on the initial enqueue in case it is dynamic
            job.good_job_concurrency_key ||= job._good_job_concurrency_key
            key = job.good_job_concurrency_key
            next if key.blank?

            enqueue_limit = job._resolve_limit(job.class.good_job_concurrency_config[:enqueue_limit])
            total_limit = job._resolve_limit(job.class.good_job_concurrency_config[:total_limit]) unless enqueue_limit
            enqueue_throttle = job._resolve_throttle(job.class.good_job_concurrency_config[:enqueue_throttle])

            limit = enqueue_limit || total_limit
            throttle = enqueue_throttle
            next unless limit || throttle

            exceeded = job._check_enqueue(limit, throttle, key: key, enqueue_limit_flag: enqueue_limit.present?)
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

          # If rules are defined, evaluate perform-stage rules and use labels
          if job.class.good_job_concurrency_rules.present?
            exceeded = nil
            valid_stages = [:perform, :total]
            job.class.good_job_concurrency_rules.each do |rule|
              rule_stage = rule[:stage].to_sym
              next unless valid_stages.include?(rule_stage)

              label_spec = rule[:label]
              label_value = label_spec.respond_to?(:call) ? job.instance_exec(&label_spec) : label_spec
              next if label_value.blank?

              limit = job._resolve_limit(rule[:limit])
              throttle = job._resolve_throttle(rule[:throttle])

              next unless limit || throttle

              limit_label = "concurrency:#{rule_stage}:limit:#{label_value}"
              throttle_label = "concurrency:#{rule_stage}:throttle:#{label_value}"

              exceeded = job._check_perform(limit, throttle, limit_label: limit_label, throttle_label: throttle_label)

              break if exceeded
            end
          else
            # Support for legacy concurrency configuration
            perform_limit = job._resolve_limit(job.class.good_job_concurrency_config[:perform_limit])
            total_limit = job._resolve_limit(job.class.good_job_concurrency_config[:total_limit]) unless perform_limit

            perform_throttle = job._resolve_throttle(job.class.good_job_concurrency_config[:perform_throttle])

            limit = perform_limit || total_limit
            throttle = perform_throttle
            next unless limit || throttle

            key = job.good_job_concurrency_key
            next if key.blank?

            exceeded = job._check_perform(limit, throttle, key: key)
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

          key_spec = config[:key]
          label_spec = if key_spec.respond_to?(:call) || key_spec.present?
                         key_spec
                       else
                         -> { _good_job_default_concurrency_key }
                       end

          # Only generate label-based rules when the class supports labels.
          # Otherwise, keep legacy behavior and rely on `good_job_concurrency_config`.
          # (We may want to deprecate `good_job_concurrency_config` in favor of rules in a future release.)
          return unless instance_methods.include?(:good_job_labels=)

          new_rules = []

          if config.key?(:enqueue_limit) || config.key?(:enqueue_throttle)
            new_rules << {
              label: label_spec,
              stage: :enqueue,
              limit: config[:enqueue_limit],
              throttle: config[:enqueue_throttle],
            }.compact
          end

          if config.key?(:perform_limit) || config.key?(:perform_throttle)
            new_rules << {
              label: label_spec,
              stage: :perform,
              limit: config[:perform_limit],
              throttle: config[:perform_throttle],
            }.compact
          end

          if config.key?(:total_limit)
            new_rules << {
              label: label_spec,
              stage: :total,
              limit: config[:total_limit],
            }
          end

          self.good_job_concurrency_rules = Array(good_job_concurrency_rules) + new_rules if new_rules.any?
        end

        # Define a concurrency rule. Rules are appended to the class-level
        # `good_job_concurrency_rules` array. Each rule is a Hash with keys
        # such as :label, :stage, :limit, and :throttle.
        def good_job_concurrency_rule(rule)
          self.good_job_concurrency_rules = Array(good_job_concurrency_rules) + [rule]
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

      # Resolves limit value from static or dynamic specification
      # @param value [Numeric, Proc, nil] limit specification
      # @return [Numeric, nil] resolved limit
      def _resolve_limit(value)
        return nil if value.nil?

        value = instance_exec(&value) if value.respond_to?(:call)
        value = nil unless value.present? && (0...Float::INFINITY).cover?(value)
        value
      end

      # Resolves throttle value from static or dynamic specification
      # @param value [Array, Proc, nil] throttle specification
      # @return [Array, nil] resolved throttle
      def _resolve_throttle(value)
        return nil if value.nil?

        value = instance_exec(&value) if value.respond_to?(:call)
        value = nil unless value.present? && value.is_a?(Array) && value.size == 2
        value
      end

      # Base query for concurrency checks
      # @param label [String, nil] concurrency label
      # @param key [Object, nil] concurrency key
      # @return [ActiveRecord::Relation] base query
      def _good_job_query_base(label, key)
        if key.present?
          GoodJob::Job.where(concurrency_key: key)
        else
          GoodJob::Job.where("labels && ARRAY[?]::text[]", [label])
        end
      end

      # Enqueue concurrency check
      # @param limit [Numeric, nil] concurrency limit
      # @param throttle [Array, nil] concurrency throttle
      # @param limit_label [String, nil] concurrency limit label
      # @param throttle_label [String, nil] concurrency throttle label
      # @param key [String, nil] concurrency key
      # @param enqueue_limit_flag [Boolean] whether the limit is an enqueue limit
      # @return [Symbol, nil] :limit or :throttle if exceeded, otherwise nil
      def _check_enqueue(limit, throttle, limit_label: nil, throttle_label: nil, key: nil, enqueue_limit_flag: false)
        exceeded = nil

        GoodJob::Job.transaction(requires_new: true, joinable: false) do
          GoodJob::Job.advisory_lock_key(limit_label || key, function: "pg_advisory_xact_lock") do
            if limit
              query = _good_job_query_base(limit_label, key)

              # Use advisory_unlocked when enqueue_limit_flag is set (legacy behavior)
              enqueue_concurrency = if enqueue_limit_flag
                                      query.unfinished.advisory_unlocked.count
                                    else
                                      query.unfinished.count
                                    end

              if (enqueue_concurrency + 1) > limit
                label_type = limit_label ? "label '#{limit_label}'" : "key '#{key}'"
                logger.info "Aborted enqueue of #{self.class.name} (Job ID: #{job_id}) because the concurrency #{label_type} has reached its enqueue limit of #{limit} #{'job'.pluralize(limit)}"
                exceeded = :limit
                next
              end
            end

            if throttle
              throttle_limit = throttle[0]
              throttle_period = throttle[1]
              enqueued_within_period = _good_job_query_base(throttle_label, key)
                                       .where(GoodJob::Job.arel_table[:created_at].gt(throttle_period.ago))
                                       .count

              if (enqueued_within_period + 1) > throttle_limit
                label_type = throttle_label ? "label '#{throttle_label}'" : "key '#{key}'"
                logger.info "Aborted enqueue of #{self.class.name} (Job ID: #{job_id}) because the concurrency #{label_type} has reached its throttle limit of #{throttle_limit} #{'job'.pluralize(throttle_limit)}"
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

      # Perform concurrency check
      # @param limit [Numeric, nil] concurrency limit
      # @param throttle [Array, nil] concurrency throttle
      # @param limit_label [String, nil] concurrency limit label
      # @param throttle_label [String, nil] concurrency throttle label
      # @param key [String, nil] concurrency key
      # @return [Symbol, nil] :limit or :throttle if exceeded, otherwise nil
      def _check_perform(limit, throttle, limit_label: nil, throttle_label: nil, key: nil)
        exceeded = nil

        GoodJob::Job.transaction(requires_new: true, joinable: false) do
          GoodJob::Job.advisory_lock_key(limit_label || key, function: "pg_advisory_xact_lock") do
            if limit
              query = _good_job_query_base(limit_label, key)

              allowed_active_job_ids = query.unfinished.advisory_locked
                                            .order(Arel.sql("COALESCE(performed_at, scheduled_at, created_at) ASC"))
                                            .limit(limit).pluck(:active_job_id)
              # The current job has already been locked and will appear in the previous query
              unless allowed_active_job_ids.include?(job_id)
                exceeded = :limit
                next
              end
            end

            if throttle
              throttle_limit = throttle[0]
              throttle_period = throttle[1]

              execution_base = if key.present?
                                 Execution.joins(:job)
                                          .where(GoodJob::Job.table_name => { concurrency_key: key })
                               else
                                 Execution.joins(:job)
                                          .where("#{GoodJob::Job.table_name}.labels && ARRAY[?]::text[]", [throttle_label])
                               end

              query = execution_base
                      .where(Execution.arel_table[:created_at].gt(Execution.bind_value('created_at', throttle_period.ago, ActiveRecord::Type::DateTime)))

              allowed_active_job_ids = query.where(error: nil).or(query.where.not(error: "GoodJob::ActiveJobExtensions::Concurrency::ThrottleExceededError: GoodJob::ActiveJobExtensions::Concurrency::ThrottleExceededError"))
                                            .order(created_at: :asc)
                                            .limit(throttle_limit)
                                            .pluck(:active_job_id)

              unless allowed_active_job_ids.include?(job_id)
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
  end
end
