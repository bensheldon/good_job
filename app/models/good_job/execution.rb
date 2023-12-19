# frozen_string_literal: true

module GoodJob
  # Active Record model that represents an +ActiveJob+ job.
  class Execution < BaseExecution
    # Raised if something attempts to execute a previously completed Execution again.
    PreviouslyPerformedError = Class.new(StandardError)

    # String separating Error Class from Error Message
    ERROR_MESSAGE_SEPARATOR = ": "

    # ActiveJob jobs without a +queue_name+ attribute are placed on this queue.
    DEFAULT_QUEUE_NAME = 'default'
    # ActiveJob jobs without a +priority+ attribute are given this priority.
    DEFAULT_PRIORITY = 0

    self.table_name = 'good_jobs'
    self.advisory_lockable_column = 'active_job_id'

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
      string = string.presence || '*'

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

    belongs_to :batch, class_name: 'GoodJob::BatchRecord', optional: true, inverse_of: :executions
    belongs_to :job, class_name: 'GoodJob::Job', foreign_key: 'active_job_id', primary_key: 'active_job_id', optional: true, inverse_of: :executions
    has_many :discrete_executions, class_name: 'GoodJob::DiscreteExecution', foreign_key: 'active_job_id', primary_key: 'active_job_id', inverse_of: :execution # rubocop:disable Rails/HasManyOrHasOneDependent

    after_destroy lambda {
      GoodJob::DiscreteExecution.where(active_job_id: active_job_id).delete_all if discrete? # TODO: move into association `dependent: :delete_all` after v4
      self.class.active_job_id(active_job_id).delete_all
    }, if: -> { @_destroy_job }

    # Get executions with given ActiveJob ID
    # @!method active_job_id(active_job_id)
    # @!scope class
    # @param active_job_id [String]
    #   ActiveJob ID
    # @return [ActiveRecord::Relation]
    scope :active_job_id, ->(active_job_id) { where(active_job_id: active_job_id) }

    # Get executions that have not yet finished (succeeded or discarded).
    # @!method unfinished
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :unfinished, -> { where(finished_at: nil) }

    # Get executions that are not scheduled for a later time than now (i.e. jobs that
    # are not scheduled or scheduled for earlier than the current time).
    # @!method only_scheduled
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :only_scheduled, -> { where(arel_table['scheduled_at'].lteq(Time.current)).or(where(scheduled_at: nil)) }

    # Order executions by priority (highest priority first).
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

    # Order executions by created_at, for first-in first-out
    # @!method creation_ordered
    # @!scope class
    # @return [ActiveRecord:Relation]
    scope :creation_ordered, -> { order(created_at: :asc) }

    # Order executions for de-queueing
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

    # Order executions in order of queues in array param
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
    scope :finished, ->(timestamp = nil) { timestamp ? where(arel_table['finished_at'].lteq(timestamp)) : where.not(finished_at: nil) }

    # Get Jobs that started but not finished yet.
    # @!method running
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :running, -> { where.not(performed_at: nil).where(finished_at: nil) }

    # Get Jobs that do not have subsequent retries
    # @!method running
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :head, -> { where(retried_good_job_id: nil) }

    # Get Jobs have errored that will not be retried further
    # @!method running
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :dead, -> { head.where.not(error: nil) }

    # Get Jobs on queues that match the given queue string.
    # @!method queue_string(string)
    # @!scope class
    # @param string [String]
    #   A string expression describing what queues to select. See
    #   {Execution.queue_parser} or
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

    def self.build_for_enqueue(active_job, overrides = {})
      new(**enqueue_args(active_job, overrides))
    end

    # Construct arguments for GoodJob::Execution from an ActiveJob instance.
    def self.enqueue_args(active_job, overrides = {})
      if active_job.priority && GoodJob.configuration.smaller_number_is_higher_priority.nil?
        GoodJob.deprecator.warn(<<~DEPRECATION)
          The next major version of GoodJob (v4.0) will change job `priority` to give smaller numbers higher priority (default: `0`), in accordance with Active Job's definition of priority.
            To opt-in to this behavior now, set `config.good_job.smaller_number_is_higher_priority = true` in your GoodJob initializer or application.rb.
            To not opt-in yet, but silence this deprecation warning, set `config.good_job.smaller_number_is_higher_priority = false`.
        DEPRECATION
      end

      execution_args = {
        active_job_id: active_job.job_id,
        queue_name: active_job.queue_name.presence || DEFAULT_QUEUE_NAME,
        priority: active_job.priority || DEFAULT_PRIORITY,
        serialized_params: active_job.serialize,
      }
      execution_args[:scheduled_at] = Time.zone.at(active_job.scheduled_at) if active_job.scheduled_at
      execution_args[:concurrency_key] = active_job.good_job_concurrency_key if active_job.respond_to?(:good_job_concurrency_key)

      if active_job.respond_to?(:good_job_labels) && active_job.good_job_labels.any? && labels_migrated?
        labels = active_job.good_job_labels.dup
        labels.map! { |label| label.to_s.strip.presence }
        labels.tap(&:compact!).tap(&:uniq!)
        execution_args[:labels] = labels
      end

      reenqueued_current_execution = CurrentThread.active_job_id && CurrentThread.active_job_id == active_job.job_id
      current_execution = CurrentThread.execution

      if reenqueued_current_execution
        if GoodJob::BatchRecord.migrated?
          execution_args[:batch_id] = current_execution.batch_id
          execution_args[:batch_callback_id] = current_execution.batch_callback_id
        end
        execution_args[:cron_key] = current_execution.cron_key
      else
        if GoodJob::BatchRecord.migrated?
          execution_args[:batch_id] = GoodJob::Batch.current_batch_id
          execution_args[:batch_callback_id] = GoodJob::Batch.current_batch_callback_id
        end
        execution_args[:cron_key] = CurrentThread.cron_key
        execution_args[:cron_at] = CurrentThread.cron_at
      end

      execution_args.merge(overrides)
    end

    # Finds the next eligible Execution, acquire an advisory lock related to it, and
    # executes the job.
    # @yield [Execution, nil] The next eligible Execution, or +nil+ if none found, before it is performed.
    # @return [ExecutionResult, nil]
    #   If a job was executed, returns an array with the {Execution} record, the
    #   return value for the job's +#perform+ method, and the exception the job
    #   raised, if any (if the job raised, then the second array entry will be
    #   +nil+). If there were no jobs to execute, returns +nil+.
    def self.perform_with_advisory_lock(parsed_queues: nil, queue_select_limit: nil)
      execution = nil
      result = nil

      unfinished.dequeueing_ordered(parsed_queues).only_scheduled.limit(1).with_advisory_lock(select_limit: queue_select_limit) do |executions|
        execution = executions.first
        if execution&.executable?
          yield(execution) if block_given?
          result = execution.perform
        else
          execution = nil
          yield(nil) if block_given?
        end
      end

      execution&.run_callbacks(:perform_unlocked)
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
      after_query = query.where('scheduled_at > ?', after).or query.where(scheduled_at: nil).where('created_at > ?', after)
      after_at = after_query.limit(limit).pluck(:scheduled_at, :created_at).map { |timestamps| timestamps.compact.first }

      if now_limit&.positive?
        now_query = query.where('scheduled_at < ?', Time.current).or query.where(scheduled_at: nil)
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
        current_execution = CurrentThread.execution

        retried = current_execution && current_execution.active_job_id == active_job.job_id
        if retried
          if current_execution.discrete?
            execution = current_execution
            execution.assign_attributes(enqueue_args(active_job, { scheduled_at: scheduled_at }))
            execution.scheduled_at ||= Time.current
            # TODO: these values ideally shouldn't be persisted until the current_execution is finished
            #   which will require handling `retry_job` being called from outside the execution context.
            execution.performed_at = nil
            execution.finished_at = nil
          else
            execution = build_for_enqueue(active_job, { scheduled_at: scheduled_at })
          end
        else
          execution = build_for_enqueue(active_job, { scheduled_at: scheduled_at })
          execution.make_discrete if discrete_support?
        end

        if create_with_advisory_lock
          if execution.persisted?
            execution.advisory_lock
          else
            execution.create_with_advisory_lock = true
          end
        end

        instrument_payload[:execution] = execution
        execution.save!

        if retried
          CurrentThread.execution_retried = true
          CurrentThread.execution.retried_good_job_id = execution.id unless current_execution.discrete?
        end

        active_job.provider_job_id = execution.id
        execution
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
    def perform
      run_callbacks(:perform) do
        raise PreviouslyPerformedError, 'Cannot perform a job that has already been performed' if finished_at

        discrete_execution = nil
        result = GoodJob::CurrentThread.within do |current_thread|
          current_thread.reset
          current_thread.execution = self

          if performed_at
            current_thread.execution_interrupted = performed_at

            if discrete?
              interrupt_error_string = self.class.format_error(GoodJob::InterruptError.new("Interrupted after starting perform at '#{performed_at}'"))
              self.error = interrupt_error_string
              self.error_event = ERROR_EVENT_INTERRUPTED if self.class.error_event_migrated?

              discrete_execution_attrs = {
                error: interrupt_error_string,
                finished_at: Time.current,
              }
              discrete_execution_attrs[:error_event] = GoodJob::ErrorEvents::ERROR_EVENT_ENUMS[GoodJob::ErrorEvents::ERROR_EVENT_INTERRUPTED] if self.class.error_event_migrated?
              discrete_executions.where(finished_at: nil).where.not(performed_at: nil).update_all(discrete_execution_attrs) # rubocop:disable Rails/SkipsModelValidations
            end
          end

          if discrete?
            transaction do
              now = Time.current
              discrete_execution = discrete_executions.create!(
                job_class: job_class,
                queue_name: queue_name,
                serialized_params: serialized_params,
                scheduled_at: (scheduled_at || created_at),
                created_at: now
              )
              update!(performed_at: now, executions_count: ((executions_count || 0) + 1))
            end
          else
            update!(performed_at: Time.current)
          end

          ActiveSupport::Notifications.instrument("perform_job.good_job", { execution: self, process_id: current_thread.process_id, thread_name: current_thread.thread_name }) do |instrument_payload|
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
              retried: current_thread.execution_retried,
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

        job_error = result.handled_error || result.unhandled_error

        if job_error
          error_string = self.class.format_error(job_error)
          self.error = error_string
          self.error_event = result.error_event if self.class.error_event_migrated?
          if discrete_execution
            discrete_execution.error = error_string
            discrete_execution.error_event = result.error_event if discrete_execution.class.error_event_migrated?
          end
        else
          self.error = nil
          self.error_event = nil if self.class.error_event_migrated?
        end

        reenqueued = result.retried? || retried_good_job_id.present?
        if result.unhandled_error && GoodJob.retry_on_unhandled_error
          if discrete_execution
            transaction do
              discrete_execution.update!(finished_at: Time.current)
              update!(performed_at: nil, finished_at: nil, retried_good_job_id: nil)
            end
          else
            save!
          end
        elsif GoodJob.preserve_job_records == true || reenqueued || (result.unhandled_error && GoodJob.preserve_job_records == :on_unhandled_error) || cron_key.present?
          now = Time.current
          if discrete_execution
            if reenqueued
              self.performed_at = nil
            else
              self.finished_at = now
            end
            discrete_execution.finished_at = now
            transaction do
              discrete_execution.save!
              save!
            end
          else
            self.finished_at = now
            save!
          end
        else
          destroy_job
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

    def make_discrete
      self.is_discrete = true
      self.id = active_job_id
      self.job_class = serialized_params['job_class']
      self.executions_count ||= 0

      current_time = Time.current
      self.created_at ||= current_time
      self.scheduled_at ||= current_time
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

    private

    def reset_batch_values(&block)
      GoodJob::Batch.within_thread(batch_id: nil, batch_callback_id: nil, &block)
    end

    def continue_discard_or_finish_batch
      batch._continue_discard_or_finish(self) if GoodJob::BatchRecord.migrated? && batch.present?
    end
  end
end
