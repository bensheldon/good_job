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

        def initialize(config)
          @label = config[:label]
          @key = config.key?(:key) ? config[:key] : GoodJob::NONE
          @total_limit = config[:total_limit]
          @enqueue_limit = config[:enqueue_limit]
          @perform_limit = config[:perform_limit]
          @enqueue_throttle = config[:enqueue_throttle]
          @perform_throttle = config[:perform_throttle]

          return unless @label.present? && key.present?

          GoodJob.deprecator.warn("Supplying both `label:` and `key:` arguments to `good_job_concurrency_rule` is deprecated. Locks use the `label:` value; `key:` is ignored. Remove `key:` from the rule.")
        end

        def key
          @key.equal?(GoodJob::NONE) ? nil : @key
        end

        # Whether the rule limits or throttles jobs at enqueue time.
        def enqueue_limited?
          @total_limit.present? || @enqueue_limit.present? || @enqueue_throttle.present?
        end

        def evaluate(job, stage)
          resolved_label = resolve_label(job)
          resolved_key = resolve_key(job, resolved_label)
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

        def resolve_key(job, label)
          if label.present? || key.blank?
            "label:#{label}"
          else
            key_value = @key.respond_to?(:call) ? job.instance_exec(&@key) : @key
            raise TypeError, "Concurrency key must be a String; was a #{key_value.class}" if key_value.present? && VALID_TYPES.none? { |type| key_value.is_a?(type) }

            key_value
          end
        end

        def resolve_label(job)
          return if @label.blank?

          label = @label.respond_to?(:call) ? job.instance_exec(&@label) : @label
          label.to_s.strip.presence
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

        # The claim key for the jobs counted by +query_scope+.
        def scoped_key(label, key)
          if label.present?
            "label:#{label}"
          elsif key_explicit? && key.present?
            "key:#{key}"
          else
            "all"
          end
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
          return nil if label.present? && job.good_job_labels.none? { |job_label| job_label.to_s.strip == label }

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
                  ActiveSupport::Notifications.instrument(
                    "enqueue_concurrency_limit_exceeded.good_job",
                    { job: job, key: key, limit: limit }
                  )
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
                  ActiveSupport::Notifications.instrument(
                    "enqueue_concurrency_throttle_exceeded.good_job",
                    { job: job, key: key, limit: throttle_limit }
                  )
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
          return nil if label.present? && job.good_job_labels.none? { |job_label| job_label.to_s.strip == label }

          query_scope = query_scope(label, key)
          claim_key = scoped_key(label, key)
          exceeded = nil
          commit = false

          GoodJob::Job.transaction(requires_new: true, joinable: false) do
            # The rule's key is the advisory lock for the checks; the claim key names the counted scope.
            GoodJob::Job.advisory_lock_key(key, function: "pg_advisory_xact_lock") do
              if limit
                commit = true
                if GoodJob::ConcurrencyClaim.table_exists?
                  granted = GoodJob::ConcurrencyClaim.claim(
                    key: claim_key,
                    limit: limit,
                    scope: query_scope,
                    job_id: job.job_id,
                    locked_by_id: CurrentThread.job&.locked_by_id
                  )
                  unless granted
                    exceeded = :limit
                    next
                  end
                else
                  # The current job's performed_at was committed before this check, acting as its claim on a slot.
                  # Count the other claims rather than ranking by performed_at, because performed_at ordering
                  # does not necessarily match commit ordering.
                  other_running_count = query_scope.running.where.not(active_job_id: job.job_id).count
                  if other_running_count >= limit
                    exceeded = :limit
                    # Release this job's claim so that the next contender for the lock does not count it.
                    GoodJob::Job.where(active_job_id: job.job_id).update_all(performed_at: nil) # rubocop:disable Rails/SkipsModelValidations
                    next
                  end
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

            # Commit claim changes made while holding the lock; otherwise rollback because it's potentially
            # less expensive than committing it even though nothing has been altered in the transaction.
            raise ActiveRecord::Rollback unless commit
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

        # Kept as the last enqueue callback (see .set_callback) so that labels applied by
        # the job's other enqueue callbacks are present when the rules are checked.
        before_enqueue :_good_job_concurrency_before_enqueue

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

          # Release claims granted by earlier rules so they are not held while this job waits
          GoodJob::ConcurrencyClaim.release_job(job.job_id) if exceeded && GoodJob::ConcurrencyClaim.table_exists?

          if exceeded == :limit
            raise GoodJob::ActiveJobExtensions::Concurrency::ConcurrencyExceededError
          elsif exceeded == :throttle
            raise GoodJob::ActiveJobExtensions::Concurrency::ThrottleExceededError
          end
        end
      end

      class_methods do
        # Whenever an enqueue callback is added, moves the concurrency check to the end of the
        # enqueue callback chain. The concurrency check then runs after enqueue callbacks that are
        # defined later in the class or its subclasses (e.g. a +before_enqueue+ that applies
        # +good_job_labels+).
        def set_callback(name, *filter_list, &block)
          super
          _good_job_concurrency_check_last if name.to_sym == :enqueue
        end

        private

        def _good_job_concurrency_check_last
          [self, *descendants].each do |klass|
            chain = klass._enqueue_callbacks
            # A subclass may have skipped the callback, or replaced it with a conditional copy via +skip_callback+.
            callback = chain.find { |cb| cb.kind == :before && cb.filter == :_good_job_concurrency_before_enqueue }
            next if callback.nil? || chain.to_a.last.equal?(callback)

            chain = chain.dup
            chain.delete(callback)
            chain.append(callback)
            klass._enqueue_callbacks = chain
          end
        end

        public

        def good_job_control_concurrency_with(
          total_limit: NONE,
          enqueue_limit: NONE,
          perform_limit: NONE,
          enqueue_throttle: NONE,
          perform_throttle: NONE,
          key: NONE
        )
          GoodJob.deprecator.warn(<<~MSG.squish)
            `good_job_control_concurrency_with` is deprecated and will be removed in GoodJob v5,
            along with the `good_jobs.concurrency_key` column. Replace it with a labelled
            `good_job_concurrency_rule` and apply the label to the job.
            See "Migrating from concurrency keys to labels" in the GoodJob README.
          MSG

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
        # include keys such as :label, :key (deprecated), and
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

          if rule[:label].blank? && rule[:key].present?
            GoodJob.deprecator.warn(<<~MSG.squish)
              Supplying `key:` without `label:` to `good_job_concurrency_rule` is deprecated and will raise in GoodJob v5,
              when the `good_jobs.concurrency_key` column it counts jobs by will be removed. Replace `key:` with `label:`
              and apply the label to the job. See "Migrating from concurrency keys to labels" in the GoodJob README.
            MSG
          end

          self.good_job_concurrency_rules = Array(good_job_concurrency_rules) + [Rule.new(rule)]
        end
      end

      # Whether the job is subject to enqueue-time concurrency checks
      # and so must be enqueued individually rather than in bulk.
      # @return [Boolean]
      def good_job_enqueue_concurrency_controlled?
        config = self.class.good_job_concurrency_config
        legacy = good_job_concurrency_key.present? && (config[:enqueue_limit] || config[:total_limit]).present?
        legacy || Array(self.class.good_job_concurrency_rules).any?(&:enqueue_limited?)
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

      def _good_job_concurrency_before_enqueue
        # Don't attempt to enforce concurrency limits with other queue adapters.
        return unless self.class.queue_adapter.is_a?(GoodJob::Adapter)

        # Always allow jobs to be retried because the current job's execution will complete momentarily
        return if CurrentThread.active_job_id == job_id

        rules = self.class.good_job_concurrency_rules

        # Only generate the concurrency key on the initial enqueue in case it is dynamic
        if self.class.good_job_concurrency_config.present?
          self.good_job_concurrency_key ||= _good_job_concurrency_key
          legacy_key = good_job_concurrency_key
          rules = [Rule.new(self.class.good_job_concurrency_config.merge(key: legacy_key)), *rules] if legacy_key.present?
        end

        exceeded = nil
        rules.each do |rule|
          exceeded = rule.evaluate(self, :enqueue)
          break if exceeded
        end

        throw :abort if exceeded
      end
    end
  end
end
