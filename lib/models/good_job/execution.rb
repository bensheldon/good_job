# frozen_string_literal: true
module GoodJob
  # ActiveRecord model that represents an +ActiveJob+ job.
  class Execution < BaseRecord
    include Lockable
    include Filterable

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
    # @example
    #   GoodJob::Execution.queue_parser('-queue1,queue2')
    #   => { exclude: [ 'queue1', 'queue2' ] }
    def self.queue_parser(string)
      string = string.presence || '*'

      if string.first == '-'
        exclude_queues = true
        string = string[1..-1]
      end

      queues = string.split(',').map(&:strip)

      if queues.include?('*')
        { all: true }
      elsif exclude_queues
        { exclude: queues }
      else
        { include: queues }
      end
    end

    belongs_to :job, class_name: 'GoodJob::Job', foreign_key: 'active_job_id', primary_key: 'active_job_id', optional: true, inverse_of: :executions

    # Get Jobs with given ActiveJob ID
    # @!method active_job_id
    # @!scope class
    # @param active_job_id [String]
    #   ActiveJob ID
    # @return [ActiveRecord::Relation]
    scope :active_job_id, ->(active_job_id) { where(active_job_id: active_job_id) }

    # Get Jobs with given class name
    # @!method job_class
    # @!scope class
    # @param string [String]
    #   Execution class name
    # @return [ActiveRecord::Relation]
    scope :job_class, ->(job_class) { where("serialized_params->>'job_class' = ?", job_class) }

    # Get Jobs that have not yet been completed.
    # @!method unfinished
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :unfinished, -> { where(finished_at: nil) }

    # Get Jobs that are not scheduled for a later time than now (i.e. jobs that
    # are not scheduled or scheduled for earlier than the current time).
    # @!method only_scheduled
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :only_scheduled, -> { where(arel_table['scheduled_at'].lteq(Time.current)).or(where(scheduled_at: nil)) }

    # Order jobs by priority (highest priority first).
    # @!method priority_ordered
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :priority_ordered, -> { order('priority DESC NULLS LAST') }

    # Order jobs by scheduled or created (oldest first).
    # @!method schedule_ordered
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :schedule_ordered, -> { order(Arel.sql('COALESCE(scheduled_at, created_at) ASC')) }

    # Get Jobs were completed before the given timestamp. If no timestamp is
    # provided, get all jobs that have been completed. By default, GoodJob
    # destroys jobs after they are completed and this will find no jobs.
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

    # Finds the next eligible Execution, acquire an advisory lock related to it, and
    # executes the job.
    # @return [ExecutionResult, nil]
    #   If a job was executed, returns an array with the {Execution} record, the
    #   return value for the job's +#perform+ method, and the exception the job
    #   raised, if any (if the job raised, then the second array entry will be
    #   +nil+). If there were no jobs to execute, returns +nil+.
    def self.perform_with_advisory_lock
      unfinished.priority_ordered.only_scheduled.limit(1).with_advisory_lock(unlock_session: true) do |executions|
        execution = executions.first
        break if execution.blank?
        break :unlocked unless execution&.executable?

        execution.perform
      end
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
    #   Epoch timestamp when the job should be executed.
    # @param create_with_advisory_lock [Boolean]
    #   Whether to establish a lock on the {Execution} record after it is created.
    # @return [Execution]
    #   The new {Execution} instance representing the queued ActiveJob job.
    def self.enqueue(active_job, scheduled_at: nil, create_with_advisory_lock: false)
      ActiveSupport::Notifications.instrument("enqueue_job.good_job", { active_job: active_job, scheduled_at: scheduled_at, create_with_advisory_lock: create_with_advisory_lock }) do |instrument_payload|
        execution_args = {
          active_job_id: active_job.job_id,
          queue_name: active_job.queue_name.presence || DEFAULT_QUEUE_NAME,
          priority: active_job.priority || DEFAULT_PRIORITY,
          serialized_params: active_job.serialize,
          scheduled_at: scheduled_at,
          create_with_advisory_lock: create_with_advisory_lock,
        }

        execution_args[:concurrency_key] = active_job.good_job_concurrency_key if active_job.respond_to?(:good_job_concurrency_key)

        if CurrentThread.cron_key
          execution_args[:cron_key] = CurrentThread.cron_key
          execution_args[:cron_at] = CurrentThread.cron_at
        elsif CurrentThread.active_job_id && CurrentThread.active_job_id == active_job.job_id
          execution_args[:cron_key] = CurrentThread.execution.cron_key
        end

        execution = GoodJob::Execution.new(**execution_args)

        instrument_payload[:execution] = execution

        execution.save!
        active_job.provider_job_id = execution.id

        CurrentThread.execution.retried_good_job_id = execution.id if CurrentThread.active_job_id && CurrentThread.active_job_id == active_job.job_id

        execution
      end
    end

    # Execute the ActiveJob job this {Execution} represents.
    # @return [ExecutionResult]
    #   An array of the return value of the job's +#perform+ method and the
    #   exception raised by the job, if any. If the job completed successfully,
    #   the second array entry (the exception) will be +nil+ and vice versa.
    def perform
      raise PreviouslyPerformedError, 'Cannot perform a job that has already been performed' if finished_at

      self.performed_at = Time.current
      save! if GoodJob.preserve_job_records

      result = execute

      job_error = result.handled_error || result.unhandled_error
      self.error = [job_error.class, ERROR_MESSAGE_SEPARATOR, job_error.message].join if job_error

      if result.unhandled_error && GoodJob.retry_on_unhandled_error
        save!
      elsif GoodJob.preserve_job_records == true || (result.unhandled_error && GoodJob.preserve_job_records == :on_unhandled_error)
        self.finished_at = Time.current
        save!
      else
        destroy!
      end

      result
    end

    # Tests whether this job is safe to be executed by this thread.
    # @return [Boolean]
    def executable?
      self.class.unscoped.unfinished.owns_advisory_locked.exists?(id: id)
    end

    def active_job
      ActiveJob::Base.deserialize(active_job_data).tap do |aj|
        aj.send(:deserialize_arguments_if_needed)
      end
    end

    # There are 3 buckets of non-overlapping statuses:
    #   1. The job will be executed
    #     - queued: The job will execute immediately when an execution thread becomes available.
    #     - scheduled: The job is scheduled to execute in the future.
    #     - retried: The job previously errored on execution and will be re-executed in the future.
    #   2. The job is being executed
    #     - running: the job is actively being executed by an execution thread
    #   3. The job will not execute
    #     - finished: The job executed successfully
    #     - discarded: The job previously errored on execution and will not be re-executed in the future.
    #
    # @return [Symbol]
    def status
      if finished_at.present?
        if error.present? && retried_good_job_id.present?
          :retried
        elsif error.present? && retried_good_job_id.nil?
          :discarded
        else
          :finished
        end
      elsif (scheduled_at || created_at) > DateTime.current
        if serialized_params.fetch('executions', 0) > 1
          :retried
        else
          :scheduled
        end
      elsif running?
        :running
      else
        :queued
      end
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

    # The last relevant timestamp for this execution
    def last_status_at
      finished_at || performed_at || scheduled_at || created_at
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

    private

    def active_job_data
      serialized_params.deep_dup
                       .tap do |job_data|
        job_data["provider_job_id"] = id
        job_data["good_job_concurrency_key"] = concurrency_key if concurrency_key
      end
    end

    # @return [ExecutionResult]
    def execute
      GoodJob::CurrentThread.within do |current_thread|
        current_thread.reset
        current_thread.execution = self

        ActiveSupport::Notifications.instrument("perform_job.good_job", { execution: self, process_id: current_thread.process_id, thread_name: current_thread.thread_name }) do
          value = ActiveJob::Base.execute(active_job_data)

          if value.is_a?(Exception)
            handled_error = value
            value = nil
          end
          handled_error ||= current_thread.error_on_retry || current_thread.error_on_discard

          ExecutionResult.new(value: value, handled_error: handled_error)
        rescue StandardError => e
          ExecutionResult.new(value: nil, unhandled_error: e)
        end
      end
    end
  end
end
