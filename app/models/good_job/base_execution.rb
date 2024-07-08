# frozen_string_literal: true

module GoodJob
  # Active Record model to share behavior between {Job} and {Execution} models
  # which both read out of the same table.
  class BaseExecution < BaseRecord
    self.abstract_class = true

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

    self.advisory_lockable_column = 'active_job_id'
    self.implicit_order_column = 'created_at'

    define_model_callbacks :perform
    define_model_callbacks :perform_unlocked, only: :after

    set_callback :perform, :around, :reset_batch_values
    set_callback :perform_unlocked, :after, :continue_discard_or_finish_batch

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
    def self.queue_parser(string)
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
    scope :only_scheduled, -> { where(arel_table['scheduled_at'].lteq(bind_value('scheduled_at', DateTime.current, ActiveRecord::Type::DateTime))).or(where(scheduled_at: nil)) }

    # Order jobs by priority (highest priority first).
    # @!method priority_ordered
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :priority_ordered, (lambda do
      if GoodJob.configuration.smaller_number_is_higher_priority
        order('priority ASC NULLS LAST')
      else
        order('priority DESC NULLS LAST')
      end
    end)

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
        "WHEN queue_name = '#{queue_name}' THEN #{index}"
      end

      order(
        Arel.sql("(CASE #{clauses.join(' ')} ELSE #{queues.length} END)")
      )
    end)

    # Order jobs by scheduled or created (oldest first).
    # @!method schedule_ordered
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :schedule_ordered, -> { order(coalesce_scheduled_at_created_at.asc) }

    # Get completed jobs before the given timestamp. If no timestamp is
    # provided, get *all* completed jobs. By default, GoodJob
    # destroys jobs after they're completed, meaning this returns no jobs.
    # However, if you have changed {GoodJob.preserve_job_records}, this may
    # find completed Jobs.
    # @!method finished(timestamp = nil)
    # @!scope class
    # @param timestamp (Float)
    #   Get jobs that finished before this time (in epoch time).
    # @return [ActiveRecord::Relation]
    scope :finished, ->(timestamp = nil) { timestamp ? where(arel_table['finished_at'].lteq(bind_value('finished_at', timestamp, ActiveRecord::Type::DateTime))) : where.not(finished_at: nil) }

    # Get Jobs that started but not finished yet.
    # @!method running
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :running, -> { where.not(performed_at: nil).where(finished_at: nil) }

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
      def json_string(json, attr)
        Arel::Nodes::Grouping.new(Arel::Nodes::InfixOperation.new('->>', json, Arel::Nodes.build_quoted(attr)))
      end

      def params_job_class
        json_string(arel_table['serialized_params'], 'job_class')
      end

      def params_execution_count
        Arel::Nodes::InfixOperation.new(
          '::',
          json_string(arel_table['serialized_params'], 'executions'),
          Arel.sql('integer')
        )
      end

      def coalesce_scheduled_at_created_at
        arel_table.coalesce(arel_table['scheduled_at'], arel_table['created_at'])
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

      unfinished.dequeueing_ordered(parsed_queues).only_scheduled.limit(1).with_advisory_lock(select_limit: queue_select_limit) do |jobs|
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
      after_query = query.where(arel_table['scheduled_at'].gt(after_bind)).or query.where(scheduled_at: nil).where(arel_table['created_at'].gt(after_bind))
      after_at = after_query.limit(limit).pluck(:scheduled_at, :created_at).map { |timestamps| timestamps.compact.first }

      if now_limit&.positive?
        now_query = query.where(arel_table['scheduled_at'].lt(bind_value('scheduled_at', Time.current, ActiveRecord::Type::DateTime))).or query.where(scheduled_at: nil)
        now_at = now_query.limit(now_limit).pluck(:scheduled_at, :created_at).map { |timestamps| timestamps.compact.first }
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
        job.save!

        CurrentThread.execution_retried = (job if retried)

        active_job.provider_job_id = job.id
        raise "These should be equal" if active_job.provider_job_id != active_job.job_id

        job
      end
    end

    def self.format_error(error)
      raise ArgumentError unless error.is_a?(Exception)

      [error.class.to_s, ERROR_MESSAGE_SEPARATOR, error.message].join
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
        discrete_execution = nil
        result = GoodJob::CurrentThread.within do |current_thread|
          current_thread.reset
          current_thread.job = self

          existing_performed_at = performed_at
          if existing_performed_at
            current_thread.execution_interrupted = existing_performed_at

            interrupt_error_string = self.class.format_error(GoodJob::InterruptError.new("Interrupted after starting perform at '#{existing_performed_at}'"))
            self.error = interrupt_error_string
            self.error_event = ERROR_EVENT_INTERRUPTED
            monotonic_duration = (::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - monotonic_start).seconds

            discrete_execution_attrs = {
              error: interrupt_error_string,
              finished_at: job_performed_at,
            }
            discrete_execution_attrs[:error_event] = GoodJob::ErrorEvents::ERROR_EVENT_ENUMS[GoodJob::ErrorEvents::ERROR_EVENT_INTERRUPTED]
            discrete_execution_attrs[:duration] = monotonic_duration
            discrete_executions.where(finished_at: nil).where.not(performed_at: nil).update_all(discrete_execution_attrs) # rubocop:disable Rails/SkipsModelValidations
          end

          transaction do
            discrete_execution_attrs = {
              job_class: job_class,
              queue_name: queue_name,
              serialized_params: serialized_params,
              scheduled_at: (scheduled_at || created_at),
              created_at: job_performed_at,
              process_id: lock_id,
            }
            job_attrs = {
              performed_at: job_performed_at,
              executions_count: ((executions_count || 0) + 1),
              locked_by_id: lock_id,
              locked_at: Time.current,
            }

            discrete_execution = discrete_executions.create!(discrete_execution_attrs)
            update!(job_attrs)
          end

          ActiveSupport::Notifications.instrument("perform_job.good_job", { job: self, execution: discrete_execution, process_id: current_thread.process_id, thread_name: current_thread.thread_name }) do |instrument_payload|
            value = ActiveJob::Base.execute(active_job_data)

            if value.is_a?(Exception)
              handled_error = value
              value = nil
            end
            handled_error ||= current_thread.error_on_retry || current_thread.error_on_discard

            error_event = if handled_error == current_thread.error_on_discard
                            ERROR_EVENT_DISCARDED
                          elsif handled_error == current_thread.error_on_retry
                            ERROR_EVENT_RETRIED
                          elsif handled_error == current_thread.error_on_retry_stopped
                            ERROR_EVENT_RETRY_STOPPED
                          elsif handled_error
                            ERROR_EVENT_HANDLED
                          end

            instrument_payload.merge!(
              value: value,
              handled_error: handled_error,
              retried: current_thread.execution_retried.present?,
              error_event: error_event
            )
            ExecutionResult.new(value: value, handled_error: handled_error, error_event: error_event, retried: current_thread.execution_retried)
          rescue StandardError => e
            error_event = if e.is_a?(GoodJob::InterruptError)
                            ERROR_EVENT_INTERRUPTED
                          elsif e == current_thread.error_on_retry_stopped
                            ERROR_EVENT_RETRY_STOPPED
                          else
                            ERROR_EVENT_UNHANDLED
                          end

            instrument_payload[:unhandled_error] = e
            ExecutionResult.new(value: nil, unhandled_error: e, error_event: error_event)
          end
        end

        job_attributes = if self.class.columns_hash.key?("locked_by_id")
                           { locked_by_id: nil, locked_at: nil }
                         else
                           {}
                         end

        job_error = result.handled_error || result.unhandled_error
        if job_error
          error_string = self.class.format_error(job_error)

          job_attributes[:error] = error_string
          job_attributes[:error_event] = result.error_event

          discrete_execution.error = error_string
          discrete_execution.error_event = result.error_event
          discrete_execution.error_backtrace = job_error.backtrace
        else
          job_attributes[:error] = nil
          job_attributes[:error_event] = nil
        end

        job_finished_at = Time.current
        monotonic_duration = (::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - monotonic_start).seconds
        job_attributes[:finished_at] = job_finished_at

        discrete_execution.finished_at = job_finished_at
        discrete_execution.duration = monotonic_duration

        retry_unhandled_error = result.unhandled_error && GoodJob.retry_on_unhandled_error
        reenqueued = result.retried? || retried_good_job_id.present? || retry_unhandled_error
        if reenqueued
          job_attributes[:performed_at] = nil
          job_attributes[:finished_at] = nil
        end

        assign_attributes(job_attributes)
        preserve_unhandled = (result.unhandled_error && (GoodJob.retry_on_unhandled_error || GoodJob.preserve_job_records == :on_unhandled_error))
        if finished_at.blank? || GoodJob.preserve_job_records == true || reenqueued || preserve_unhandled || cron_key.present?
          transaction do
            discrete_execution.save!
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

    # Return formatted serialized_params for display in the dashboard
    # @return [Hash]
    def display_serialized_params
      serialized_params.merge({
                                _good_job: attributes.except('serialized_params', 'locktype', 'owns_advisory_lock'),
                              })
    end

    def running?
      if has_attribute?(:locktype)
        self['locktype'].present?
      else
        advisory_locked?
      end
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

    # Destroys this execution and all executions within the same job
    def destroy_job
      @_destroy_job = true
      destroy!
    ensure
      @_destroy_job = false
    end

    def job_state
      state = { queue_name: queue_name }
      state[:scheduled_at] = scheduled_at if scheduled_at
      state
    end

    private

    def reset_batch_values(&block)
      GoodJob::Batch.within_thread(batch_id: nil, batch_callback_id: nil, &block)
    end

    def continue_discard_or_finish_batch
      batch._continue_discard_or_finish(self) if batch.present?
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
