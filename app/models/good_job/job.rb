# frozen_string_literal: true

module GoodJob
  # Active Record model that represents an +ActiveJob+ job.
  class Job < BaseRecord
    include AdvisoryLockable
    include ErrorEvents
    include Filterable
    include Reportable

    # Raised if something attempts to execute a previously completed Execution again.
    PreviouslyPerformedError = Class.new(StandardError)

    # String separating Error Class from Error Message
    ERROR_MESSAGE_SEPARATOR = ": "

    # ActiveJob jobs without a +queue_name+ attribute are placed on this queue.
    DEFAULT_QUEUE_NAME = 'default'
    # ActiveJob jobs without a +priority+ attribute are given this priority.
    DEFAULT_PRIORITY = 0

    # Raised when an inappropriate action is applied to a Job based on its state.
    ActionForStateMismatchError = Class.new(StandardError)
    # Raised when GoodJob is not configured as the Active Job Queue Adapter
    AdapterNotGoodJobError = Class.new(StandardError)
    # Attached to a Job's Execution when the Job is discarded.
    DiscardJobError = Class.new(StandardError)
    # Raised when Active Job data cannot be deserialized
    ActiveJobDeserializationError = Class.new(StandardError)

    self.table_name = 'good_jobs'
    self.advisory_lockable_column = 'id'
    self.implicit_order_column = 'created_at'
    self.ignored_columns += %w[is_discrete retried_good_job_id]

    define_model_callbacks :perform
    define_model_callbacks :perform_unlocked, only: :after

    set_callback :perform, :around, :reset_batch_values
    set_callback :perform_unlocked, :after, :continue_discard_or_finish_batch

    belongs_to :batch, class_name: 'GoodJob::BatchRecord', inverse_of: :jobs, optional: true
    belongs_to :callback_batch, class_name: 'GoodJob::BatchRecord', foreign_key: :batch_callback_id, inverse_of: :callback_jobs, optional: true
    belongs_to :locked_by_process, class_name: "GoodJob::Process", foreign_key: :locked_by_id, inverse_of: :locked_jobs, optional: true
    has_many :executions, class_name: 'GoodJob::Execution', foreign_key: 'active_job_id', primary_key: "id", inverse_of: :job, dependent: :delete_all

    before_create -> { self.id = active_job_id }, if: -> { active_job_id.present? }

    # Get Jobs finished before the given timestamp.
    # @!method finished_before(timestamp)
    # @!scope class
    # @param timestamp (DateTime, Time)
    # @return [ActiveRecord::Relation]
    scope :finished_before, ->(timestamp) { where(arel_table['finished_at'].lteq(bind_value('finished_at', timestamp, ActiveRecord::Type::DateTime))) }

    # First execution will run in the future
    scope :scheduled, -> { where(finished_at: nil).where(arel_table['scheduled_at'].gt(bind_value('scheduled_at', Time.current, ActiveRecord::Type::DateTime))).where(params_execution_count.lt(2)) }
    # Execution errored, will run in the future
    scope :retried, -> { where(finished_at: nil).where(arel_table['scheduled_at'].gt(bind_value('scheduled_at', Time.current, ActiveRecord::Type::DateTime))).where(params_execution_count.gt(1)) }
    # Immediate/Scheduled time to run has passed, waiting for an available thread run
    scope :queued, -> { where(performed_at: nil, finished_at: nil).where(arel_table['scheduled_at'].lteq(bind_value('scheduled_at', Time.current, ActiveRecord::Type::DateTime))) }
    # Advisory locked and executing
    scope :running, -> { where.not(performed_at: nil).where(finished_at: nil) }
    # Finished executing (succeeded or discarded)
    scope :finished, -> { where.not(finished_at: nil) }
    # Completed executing successfully
    scope :succeeded, -> { finished.where(error: nil) }
    # Errored but will not be retried
    scope :discarded, -> { finished.where.not(error: nil) }

    # With a given class name
    # @!method job_class(name)
    # @!scope class
    # @param name [String] Job class name
    # @return [ActiveRecord::Relation]
    scope :job_class, ->(name) { where(params_job_class.eq(name)) }

    # Get jobs with given ActiveJob ID
    # @!method active_job_id(active_job_id)
    # @!scope class
    # @param active_job_id [String]
    #   ActiveJob ID
    # @return [ActiveRecord::Relation]
    scope :active_job_id, ->(active_job_id) { where(active_job_id: active_job_id) }

    # Get jobs that have not yet finished (succeeded or discarded).
    # @!method unfinished
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :unfinished, -> { where(finished_at: nil) }

    # Get jobs that are not scheduled for a later time than now (i.e. jobs that
    # are not scheduled or scheduled for earlier than the current time).
    # @!method only_scheduled
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :only_scheduled, -> { where(arel_table['scheduled_at'].lteq(bind_value('scheduled_at', DateTime.current, ActiveRecord::Type::DateTime))) }

    # Exclude jobs that are paused via queue_name or job_class.
    # Only applies when enable_pauses configuration is true.
    # @!method exclude_paused
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :exclude_paused, lambda {
      return all unless GoodJob.configuration.enable_pauses

      paused_query = GoodJob::Setting.where(key: GoodJob::Setting::PAUSES)
      paused_queues_query = paused_query.select("jsonb_array_elements_text(value->'queues')")
      paused_job_classes_query = paused_query.select("jsonb_array_elements_text(value->'job_classes')")
      paused_labels_query = paused_query.select("jsonb_array_elements_text(value->'labels')")

      where.not(queue_name: paused_queues_query)
           .where.not(job_class: paused_job_classes_query)
           .where(
             Arel::Nodes::Not.new(
               Arel::Nodes::NamedFunction.new(
                 "COALESCE", [
                   Arel::Nodes::InfixOperation.new('&&', arel_table['labels'], Arel::Nodes::NamedFunction.new('ARRAY', [paused_labels_query.arel])),
                   Arel::Nodes::SqlLiteral.new('FALSE'),
                 ]
               )
             )
           )
    }

    # Order jobs by priority (highest priority first).
    # @!method priority_ordered
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :priority_ordered, -> { order('priority ASC NULLS LAST') }

    # Order jobs by created_at, for first-in first-out
    # @!method creation_ordered
    # @!scope class
    # @return [ActiveRecord:Relation]
    scope :creation_ordered, -> { order(created_at: :asc) }

    # Order jobs for de-queueing
    # @!method dequeueing_ordered(parsed_queues)
    # @!scope class
    # @param parsed_queues [Hash]
    #   optional output of .queue_parser, parsed queues, will be used for
    #   ordered queues.
    # @return [ActiveRecord::Relation]
    scope :dequeueing_ordered, (lambda do |parsed_queues|
      relation = self
      relation = relation.queue_ordered(parsed_queues[:include]) if parsed_queues && parsed_queues[:ordered_queues] && parsed_queues[:include]
      relation = relation.priority_ordered.creation_ordered

      relation
    end)

    # Order jobs in order of queues in array param
    # @!method queue_ordered(queues)
    # @!scope class
    # @param queues [Array<string] ordered names of queues
    # @return [ActiveRecord::Relation]
    scope :queue_ordered, (lambda do |queues|
      clauses = queues.map.with_index do |queue_name, index|
        sanitize_sql_array(["WHEN queue_name = ? THEN ?", queue_name, index])
      end
      order(Arel.sql("(CASE #{clauses.join(' ')} ELSE #{queues.size} END)"))
    end)

    # Order jobs by scheduled or created (oldest first).
    # @!method schedule_ordered
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :schedule_ordered, -> { order(scheduled_at: :asc) }

    # Get Jobs on queues that match the given queue string.
    # @!method queue_string(string)
    # @!scope class
    # @param string [String]
    #   A string expression describing what queues to select. See
    #   {Job.queue_parser} or
    #   {file:README.md#optimize-queues-threads-and-processes} for more details
    #   on the format of the string. Note this only handles individual
    #   semicolon-separated segments of that string format.
    # @return [ActiveRecord::Relation]
    scope :queue_string, (lambda do |string|
      parsed = queue_parser(string)

      if parsed[:all]
        all
      elsif parsed[:exclude]
        where.not(queue_name: parsed[:exclude]).or where(queue_name: nil)
      elsif parsed[:include]
        where(queue_name: parsed[:include])
      end
    end)

    class << self
      # Parse a string representing a group of queues into a more readable data
      # structure.
      # @param string [String] Queue string
      # @return [Hash]
      #   How to match a given queue. It can have the following keys and values:
      #   - +{ all: true }+ indicates that all queues match.
      #   - +{ exclude: Array<String> }+ indicates the listed queue names should
      #     not match.
      #   - +{ include: Array<String> }+ indicates the listed queue names should
      #     match.
      #   - +{ include: Array<String>, ordered_queues: true }+ indicates the listed
      #     queue names should match, and dequeue should respect queue order.
      # @example
      #   GoodJob::Execution.queue_parser('-queue1,queue2')
      #   => { exclude: [ 'queue1', 'queue2' ] }
      def queue_parser(string)
        string = string.strip.presence || '*'

        case string.first
        when '-'
          exclude_queues = true
          string = string[1..]
        when '+'
          ordered_queues = true
          string = string[1..]
        end

        queues = string.split(',').map(&:strip)

        if queues.include?('*')
          { all: true }
        elsif exclude_queues
          { exclude: queues }
        elsif ordered_queues
          {
            include: queues,
            ordered_queues: true,
          }
        else
          { include: queues }
        end
      end

      def json_string(json, attr)
        Arel::Nodes::Grouping.new(Arel::Nodes::InfixOperation.new('->>', json, Arel::Nodes.build_quoted(attr)))
      end

      def params_job_class
        arel_table[:job_class]
      end

      def params_execution_count
        Arel::Nodes::InfixOperation.new(
          '::',
          json_string(arel_table['serialized_params'], 'executions'),
          Arel.sql('integer')
        )
      end

      def historic_finished_at_index_migrated?
        return true unless connection.index_name_exists?(:good_jobs, :index_good_jobs_jobs_on_finished_at)

        migration_pending_warning!
        false
      end
    end

    def self.build_for_enqueue(active_job, scheduled_at: nil)
      new(**enqueue_args(active_job, scheduled_at: scheduled_at))
    end

    # Construct arguments for GoodJob::Execution from an ActiveJob instance.
    def self.enqueue_args(active_job, scheduled_at: nil)
      execution_args = {
        id: active_job.job_id,
        active_job_id: active_job.job_id,
        job_class: active_job.class.name,
        queue_name: active_job.queue_name.presence || DEFAULT_QUEUE_NAME,
        priority: active_job.priority || DEFAULT_PRIORITY,
        serialized_params: active_job.serialize,
        created_at: Time.current,
      }

      execution_args[:scheduled_at] = if scheduled_at
                                        scheduled_at
                                      elsif active_job.scheduled_at
                                        Time.zone.at(active_job.scheduled_at)
                                      else
                                        execution_args[:created_at]
                                      end

      execution_args[:concurrency_key] = active_job.good_job_concurrency_key if active_job.respond_to?(:good_job_concurrency_key)

      if active_job.respond_to?(:good_job_labels) && active_job.good_job_labels.any?
        labels = active_job.good_job_labels.dup
        labels.map! { |label| label.to_s.strip.presence }
        labels.tap(&:compact!).tap(&:uniq!)
        execution_args[:labels] = labels
      end

      reenqueued_current_job = CurrentThread.active_job_id && CurrentThread.active_job_id == active_job.job_id
      current_job = CurrentThread.job

      if reenqueued_current_job
        execution_args[:batch_id] = current_job.batch_id
        execution_args[:batch_callback_id] = current_job.batch_callback_id
        execution_args[:cron_key] = current_job.cron_key
      else
        execution_args[:batch_id] = GoodJob::Batch.current_batch_id
        execution_args[:batch_callback_id] = GoodJob::Batch.current_batch_callback_id
        execution_args[:cron_key] = CurrentThread.cron_key
        execution_args[:cron_at] = CurrentThread.cron_at
      end

      execution_args
    end

    # Finds the next eligible Execution, acquire an advisory lock related to it, and
    # executes the job.
    # @yield [Execution, nil] The next eligible Execution, or +nil+ if none found, before it is performed.
    # @return [ExecutionResult, nil]
    #   If a job was executed, returns an array with the {Execution} record, the
    #   return value for the job's +#perform+ method, and the exception the job
    #   raised, if any (if the job raised, then the second array entry will be
    #   +nil+). If there were no jobs to execute, returns +nil+.
    def self.perform_with_advisory_lock(lock_id:, parsed_queues: nil, queue_select_limit: nil)
      job = nil
      result = nil

      unfinished.dequeueing_ordered(parsed_queues).only_scheduled.exclude_paused.limit(1).with_advisory_lock(select_limit: queue_select_limit) do |jobs|
        job = jobs.first

        if job&.executable?
          yield(job) if block_given?

          result = job.perform(lock_id: lock_id)
        else
          job = nil
          yield(nil) if block_given?
        end
      end

      job&.run_callbacks(:perform_unlocked)
      result
    end

    # Fetches the scheduled execution time of the next eligible Execution(s).
    # @param after [DateTime]
    # @param limit [Integer]
    # @param now_limit [Integer, nil]
    # @return [Array<DateTime>]
    def self.next_scheduled_at(after: nil, limit: 100, now_limit: nil)
      query = advisory_unlocked.unfinished.schedule_ordered

      after ||= Time.current
      after_bind = bind_value('scheduled_at', after, ActiveRecord::Type::DateTime)
      after_query = query.where(arel_table['scheduled_at'].gt(after_bind))
      after_at = after_query.limit(limit).pluck(:scheduled_at)

      if now_limit&.positive?
        now_bind = bind_value('scheduled_at', Time.current, ActiveRecord::Type::DateTime)
        now_query = query.where(arel_table['scheduled_at'].lt(now_bind))
        now_at = now_query.limit(now_limit).pluck(:scheduled_at)
      end

      Array(now_at) + after_at
    end

    # Places an ActiveJob job on a queue by creating a new {Execution} record.
    # @param active_job [ActiveJob::Base]
    #   The job to enqueue.
    # @param scheduled_at [Float]
    #   Epoch timestamp when the job should be executed, if blank will delegate to the ActiveJob instance
    # @param create_with_advisory_lock [Boolean]
    #   Whether to establish a lock on the {Execution} record after it is created.
    # @return [Execution]
    #   The new {Execution} instance representing the queued ActiveJob job.
    def self.enqueue(active_job, scheduled_at: nil, create_with_advisory_lock: false)
      ActiveSupport::Notifications.instrument("enqueue_job.good_job", { active_job: active_job, scheduled_at: scheduled_at, create_with_advisory_lock: create_with_advisory_lock }) do |instrument_payload|
        current_job = CurrentThread.job

        retried = current_job && current_job.active_job_id == active_job.job_id
        if retried
          job = current_job
          job.assign_attributes(enqueue_args(active_job, scheduled_at: scheduled_at))
          job.scheduled_at ||= Time.current
          # TODO: these values ideally shouldn't be persisted until the current_job is finished
          #   which will require handling `retry_job` being called from outside the job context.
          job.performed_at = nil
          job.finished_at = nil
        else
          job = build_for_enqueue(active_job, scheduled_at: scheduled_at)
        end

        if create_with_advisory_lock
          if job.persisted?
            job.advisory_lock
          else
            job.create_with_advisory_lock = true
          end
        end

        instrument_payload[:job] = job
        begin
          job.save!
        rescue ActiveRecord::RecordNotUnique
          raise unless job.cron_key

          # Active Job doesn't have a clean way to cancel an enqueue for unexceptional reasons
          # This is a workaround to mark it as having been halted in before_enqueue
          active_job.send(:halted_callback_hook, "duplicate_cron_key", "good_job")
          return false
        end

        CurrentThread.retried_job = job if retried

        active_job.provider_job_id = job.id
        raise "These should be equal" if active_job.provider_job_id != active_job.job_id

        job
      end
    end

    def self.format_error(error)
      raise ArgumentError unless error.is_a?(Exception)

      [error.class.to_s, ERROR_MESSAGE_SEPARATOR, error.message].join
    end

    # When code needs to optionally handle enqueue_after_transaction_commit
    def self.defer_after_commit_maybe(good_job_or_active_job_classes)
      if enqueue_after_commit?(good_job_or_active_job_classes)
        ActiveRecord.after_all_transactions_commit { yield(true) }
      else
        yield(false)
      end
    end

    def self.enqueue_after_commit?(good_job_or_active_job_classes)
      good_job_or_active_job_classes = Array(good_job_or_active_job_classes)

      feature_exists = ActiveRecord.respond_to?(:after_all_transactions_commit)
      feature_exists && good_job_or_active_job_classes.any? do |klass|
        active_job_class = case klass
                           when String
                             klass.constantize
                           when Job
                             klass.job_class.constantize
                           else
                             klass
                           end

        active_job_class.respond_to?(:enqueue_after_transaction_commit)
      end
    end

    # TODO: it would be nice to enforce these values at the model
    # validates :active_job_id, presence: true
    # validates :scheduled_at, presence: true
    # validates :job_class, presence: true
    # validates :error_event, presence: true, if: -> { error.present? }

    # The most recent error message.
    # If the job has been retried, the error will be fetched from the previous {Execution} record.
    # @return [String]
    def recent_error
      GoodJob.deprecator.warn(<<~DEPRECATION)
        The `GoodJob::Job#recent_error` method is deprecated and will be removed in the next major release.

        Replace usage of GoodJob::Job#recent_error with `GoodJob::Job#error`.
      DEPRECATION
      error
    end

    # Errors for the job to be displayed in the Dashboard.
    # @return [String]
    def display_error
      return error if error.present?

      serialized_params.fetch('exception_executions', {}).map do |exception, count|
        "#{exception}: #{count}"
      end.join(', ')
    end

    # Return formatted serialized_params for display in the dashboard
    # @return [Hash]
    def display_serialized_params
      serialized_params.merge({
                                _good_job: attributes.except('serialized_params', 'locktype', 'owns_advisory_lock'),
                              })
    end

    # Used when displaying this job in the GoodJob dashboard.
    # @return [String]
    def display_name
      job_class
    end

    def executions_count
      super || 0
    end

    # Tests whether the job is being executed right now.
    # @return [Boolean]
    def running?
      # Avoid N+1 Query: `.includes_advisory_locks`
      if has_attribute?(:locktype)
        self['locktype'].present?
      else
        advisory_locked?
      end
    end

    # Tests whether the job has finished (succeeded or discarded).
    # @return [Boolean]
    def finished?
      finished_at.present?
    end

    # Tests whether the job has finished but with an error.
    # @return [Boolean]
    def discarded?
      finished? && error.present?
    end

    # Tests whether the job has finished without error
    # @return [Boolean]
    def succeeded?
      finished? && !discarded?
    end

    # Retry a job that has errored and been discarded.
    # This action will create a new {Execution} record for the job.
    # @return [ActiveJob::Base]
    def retry_job
      Rails.application.executor.wrap do
        with_advisory_lock do
          reload
          active_job = self.active_job(ignore_deserialization_errors: true)

          raise ActiveJobDeserializationError if active_job.nil?
          raise AdapterNotGoodJobError unless active_job.class.queue_adapter.is_a? GoodJob::Adapter
          raise ActionForStateMismatchError if finished_at.blank? || error.blank?

          # Update the executions count because the previous execution will not have been preserved
          # Do not update `exception_executions` because that comes from rescue_from's arguments
          active_job.executions = (active_job.executions || 0) + 1

          begin
            error_class, error_message = error.split(ERROR_MESSAGE_SEPARATOR).map(&:strip)
            error = error_class.constantize.new(error_message)
          rescue StandardError
            error = StandardError.new(error)
          end

          new_active_job = nil

          transaction do
            Job.defer_after_commit_maybe(active_job.class) do
              GoodJob::CurrentThread.within do |current_thread|
                current_thread.job = self
                current_thread.retry_now = true

                # NOTE: I18n.with_locale necessary until fixed in rails https://github.com/rails/rails/pull/52121
                I18n.with_locale(active_job.locale) do
                  new_active_job = active_job.retry_job(wait: 0, error: error)
                end
              end
            end
            self.error_event = :retried if error
            save!
          end

          new_active_job
        end
      end
    end

    # Discard a job so that it will not be executed further.
    # This action will add a {DiscardJobError} to the job's {Execution} and mark it as finished.
    # @return [void]
    def discard_job(message)
      with_advisory_lock do
        _discard_job(message)
      end
    end

    # Force discard a job so that it will not be executed further. Force discard allows discarding
    # a running job.
    # This action will add a {DiscardJobError} to the job's {Execution} and mark it as finished.
    def force_discard_job(message)
      _discard_job(message)
    end

    # Reschedule a scheduled job so that it executes immediately (or later) by the next available execution thread.
    # @param scheduled_at [DateTime, Time] When to reschedule the job
    # @return [void]
    def reschedule_job(scheduled_at = Time.current)
      with_advisory_lock do
        reload
        raise ActionForStateMismatchError if finished_at.present?

        update(scheduled_at: scheduled_at)
      end
    end

    # Destroy all of a discarded or finished job's executions from the database so that it will no longer appear on the dashboard.
    # @return [void]
    def destroy_job
      with_advisory_lock do
        raise ActionForStateMismatchError if finished_at.blank?

        destroy
      end
    end

    # Build an ActiveJob instance and deserialize the arguments, using `#active_job_data`.
    #
    # @param ignore_deserialization_errors [Boolean]
    #   Whether to ignore ActiveJob::DeserializationError and NameError when deserializing the arguments.
    #   This is most useful if you aren't planning to use the arguments directly.
    def active_job(ignore_deserialization_errors: false)
      ActiveJob::Base.deserialize(active_job_data).tap do |aj|
        aj.send(:deserialize_arguments_if_needed)
      rescue ActiveJob::DeserializationError
        raise unless ignore_deserialization_errors
      end
    rescue NameError
      raise unless ignore_deserialization_errors
    end

    # Execute the ActiveJob job this {Execution} represents.
    # @return [ExecutionResult]
    #   An array of the return value of the job's +#perform+ method and the
    #   exception raised by the job, if any. If the job completed successfully,
    #   the second array entry (the exception) will be +nil+ and vice versa.
    def perform(lock_id:)
      run_callbacks(:perform) do
        raise PreviouslyPerformedError, 'Cannot perform a job that has already been performed' if finished_at

        job_performed_at = Time.current
        monotonic_start = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
        execution = nil
        result = GoodJob::CurrentThread.within do |current_thread|
          current_thread.reset
          current_thread.job = self

          existing_performed_at = performed_at
          if existing_performed_at
            current_thread.execution_interrupted = existing_performed_at

            interrupt_error_string = self.class.format_error(GoodJob::InterruptError.new("Interrupted after starting perform at '#{existing_performed_at}'"))
            self.error = interrupt_error_string
            self.error_event = :interrupted
            monotonic_duration = (::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - monotonic_start).seconds

            execution_attrs = {
              error: interrupt_error_string,
              finished_at: job_performed_at,
              error_event: :interrupted,
              duration: monotonic_duration,
            }
            executions.where(finished_at: nil).where.not(performed_at: nil).update_all(execution_attrs) # rubocop:disable Rails/SkipsModelValidations
          end

          transaction do
            execution_attrs = {
              job_class: job_class,
              queue_name: queue_name,
              serialized_params: serialized_params,
              scheduled_at: scheduled_at || created_at,
              created_at: job_performed_at,
              process_id: lock_id,
            }
            job_attrs = {
              performed_at: job_performed_at,
              executions_count: ((executions_count || 0) + 1),
              locked_by_id: lock_id,
              locked_at: Time.current,
            }

            execution = executions.create!(execution_attrs)
            update!(job_attrs)
          end

          ActiveSupport::Notifications.instrument("perform_job.good_job", { job: self, execution: execution, process_id: current_thread.process_id, thread_name: current_thread.thread_name }) do |instrument_payload|
            value = ActiveJob::Base.execute(active_job_data)

            if value.is_a?(Exception)
              handled_error = value
              value = nil
            end
            handled_error ||= current_thread.error_on_retry || current_thread.error_on_discard
            error_event = if !handled_error
                            nil
                          elsif handled_error == current_thread.error_on_discard
                            :discarded
                          elsif handled_error == current_thread.error_on_retry
                            :retried
                          elsif handled_error == current_thread.error_on_retry_stopped
                            :retry_stopped
                          elsif handled_error
                            :handled
                          end

            instrument_payload.merge!(
              value: value,
              error: handled_error,
              handled_error: handled_error,
              retried: current_thread.retried_job.present?,
              error_event: error_event
            )
            ExecutionResult.new(value: value, handled_error: handled_error, error_event: error_event, retried_job: current_thread.retried_job)
          rescue StandardError => e
            error_event = if e.is_a?(GoodJob::InterruptError)
                            :interrupted
                          elsif e == current_thread.error_on_retry_stopped
                            :retry_stopped
                          else
                            :unhandled
                          end

            instrument_payload.merge!(
              error: e,
              unhandled_error: e,
              error_event: error_event
            )
            ExecutionResult.new(value: nil, unhandled_error: e, error_event: error_event)
          end
        end

        job_attributes = { locked_by_id: nil, locked_at: nil }

        job_error = result.handled_error || result.unhandled_error
        if job_error
          error_string = self.class.format_error(job_error)

          job_attributes[:error] = error_string
          job_attributes[:error_event] = result.error_event

          execution.error = error_string
          execution.error_event = result.error_event
          execution.error_backtrace = job_error.backtrace
        else
          job_attributes[:error] = nil
          job_attributes[:error_event] = nil
        end

        job_finished_at = Time.current
        monotonic_duration = (::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - monotonic_start).seconds
        job_attributes[:finished_at] = job_finished_at

        execution.finished_at = job_finished_at
        execution.duration = monotonic_duration

        retry_unhandled_error = result.unhandled_error && GoodJob.retry_on_unhandled_error
        reenqueued = result.retried? || retry_unhandled_error
        if reenqueued
          job_attributes[:performed_at] = nil
          job_attributes[:finished_at] = nil
        end

        assign_attributes(job_attributes)
        preserve_unhandled = result.unhandled_error && (GoodJob.retry_on_unhandled_error || GoodJob.preserve_job_records == :on_unhandled_error)
        if finished_at.blank? || GoodJob.preserve_job_records == true || reenqueued || preserve_unhandled || cron_key.present?
          transaction do
            execution.save!
            save!
          end
        else
          destroy!
        end

        result
      end
    end

    # Tests whether this job is safe to be executed by this thread.
    # @return [Boolean]
    def executable?
      reload.finished_at.blank?
    rescue ActiveRecord::RecordNotFound
      false
    end

    def number
      serialized_params.fetch('executions', 0) + 1
    end

    # Time between when this job was expected to run and when it started running
    def queue_latency
      now = Time.zone.now
      expected_start = scheduled_at || created_at
      actual_start = performed_at || finished_at || now

      actual_start - expected_start unless expected_start >= now
    end

    # Time between when this job started and finished
    def runtime_latency
      (finished_at || Time.zone.now) - performed_at if performed_at
    end

    def job_state
      state = { queue_name: queue_name }
      state[:scheduled_at] = scheduled_at if scheduled_at
      state
    end

    private

    def _discard_job(message)
      active_job = self.active_job(ignore_deserialization_errors: true)

      raise ActionForStateMismatchError if finished_at.present?

      job_error = GoodJob::Job::DiscardJobError.new(message)

      update_record = proc do
        update(
          finished_at: Time.current,
          error: self.class.format_error(job_error),
          error_event: :discarded
        )
      end

      if active_job.respond_to?(:instrument)
        active_job.send :instrument, :discard, error: job_error, &update_record
      else
        update_record.call
      end
    end

    def reset_batch_values(&block)
      GoodJob::Batch.within_thread(batch_id: nil, batch_callback_id: nil, &block)
    end

    def continue_discard_or_finish_batch
      batch._continue_discard_or_finish(self) if batch.present?
      callback_batch._continue_discard_or_finish if callback_batch.present?
    end

    def active_job_data
      serialized_params.deep_dup
                       .tap do |job_data|
        job_data["provider_job_id"] = id
        job_data["good_job_concurrency_key"] = concurrency_key if concurrency_key
        job_data["good_job_labels"] = Array(labels) if labels.present?
      end
    end
  end
end

ActiveSupport.run_load_hooks(:good_job_job, GoodJob::Job)
