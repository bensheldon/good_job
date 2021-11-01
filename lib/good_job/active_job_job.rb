# frozen_string_literal: true
module GoodJob
  # ActiveRecord model that represents an +ActiveJob+ job.
  # There is not a table in the database whose discrete rows represents "Jobs".
  # The +good_jobs+ table is a table of individual {GoodJob::Execution}s that share the same +active_job_id+.
  # A single row from the +good_jobs+ table of executions is fetched to represent an ActiveJobJob
  # Parent class can be configured with +GoodJob.active_record_parent_class+.
  # @!parse
  #   class ActiveJob < ActiveRecord::Base; end
  class ActiveJobJob < Object.const_get(GoodJob.active_record_parent_class)
    include Filterable
    include Lockable

    # Raised when an inappropriate action is applied to a Job based on its state.
    ActionForStateMismatchError = Class.new(StandardError)
    # Raised when an action requires GoodJob to be the ActiveJob Queue Adapter but GoodJob is not.
    AdapterNotGoodJobError = Class.new(StandardError)
    # Attached to a Job's Execution when the Job is discarded.
    DiscardJobError = Class.new(StandardError)

    self.table_name = 'good_jobs'
    self.primary_key = 'active_job_id'
    self.advisory_lockable_column = 'active_job_id'

    has_many :executions, -> { order(created_at: :asc) }, class_name: 'GoodJob::Execution', foreign_key: 'active_job_id'

    # Only the most-recent unretried execution represents a "Job"
    default_scope { where(retried_good_job_id: nil) }

    # Get Jobs with given class name
    # @!method job_class
    # @!scope class
    # @param string [String]
    #   Execution class name
    # @return [ActiveRecord::Relation]
    scope :job_class, ->(job_class) { where("serialized_params->>'job_class' = ?", job_class) }

    # First execution will run in the future
    scope :scheduled, -> { where(finished_at: nil).where('COALESCE(scheduled_at, created_at) > ?', DateTime.current).where("(serialized_params->>'executions')::integer < 2") }
    # Execution errored, will run in the future
    scope :retried, -> { where(finished_at: nil).where('COALESCE(scheduled_at, created_at) > ?', DateTime.current).where("(serialized_params->>'executions')::integer > 1") }
    # Immediate/Scheduled time to run has passed, waiting for an available thread run
    scope :queued, -> { where(finished_at: nil).where('COALESCE(scheduled_at, created_at) <= ?', DateTime.current).joins_advisory_locks.where(pg_locks: { locktype: nil }) }
    # Advisory locked and executing
    scope :running, -> { where(finished_at: nil).joins_advisory_locks.where.not(pg_locks: { locktype: nil }) }
    # Completed executing successfully
    scope :finished, -> { where.not(finished_at: nil).where(error: nil) }
    # Errored but will not be retried
    scope :discarded, -> { where.not(finished_at: nil).where.not(error: nil) }

    # The job's ActiveJob UUID
    # @return [String]
    def id
      active_job_id
    end

    # The ActiveJob job class, as a string
    # @return [String]
    def job_class
      serialized_params['job_class']
    end

    # The status of the Job, based on the state of its most recent execution.
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
      execution = head_execution
      if execution.finished_at.present?
        if execution.error.present?
          :discarded
        else
          :finished
        end
      elsif (execution.scheduled_at || execution.created_at) > DateTime.current
        if execution.serialized_params.fetch('executions', 0) > 1
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

    # This job's most recent {Execution}
    # @param reload [Booelan] whether to reload executions
    # @return [Execution]
    def head_execution(reload: false)
      executions.reload if reload
      executions.load # memoize the results
      executions.last
    end

    # This job's initial/oldest {Execution}
    # @return [Execution]
    def tail_execution
      executions.first
    end

    # The number of times this job has been executed, according to ActiveJob's serialized state.
    # @return [Numeric]
    def executions_count
      aj_count = head_execution.serialized_params.fetch('executions', 0)
      # The execution count within serialized_params is not updated
      # once the underlying execution has been executed.
      if status.in? [:discarded, :finished, :running]
        aj_count + 1
      else
        aj_count
      end
    end

    # The number of times this job has been executed, according to the number of GoodJob {Execution} records.
    # @return [Numeric]
    def preserved_executions_count
      executions.size
    end

    # The most recent error message.
    # If the job has been retried, the error will be fetched from the previous {Execution} record.
    # @return [String]
    def recent_error
      head_execution.error || executions[-2]&.error
    end

    # Tests whether the job is being executed right now.
    # @return [Boolean]
    def running?
      # Avoid N+1 Query: `.joins_advisory_locks.select('good_jobs.*', 'pg_locks.locktype AS locktype')`
      if has_attribute?(:locktype)
        self['locktype'].present?
      else
        advisory_locked?
      end
    end

    # Retry a job that has errored and been discarded.
    # This action will create a new job {Execution} record.
    # @return [ActiveJob::Base]
    def retry_job
      with_advisory_lock do
        execution = head_execution(reload: true)
        active_job = execution.active_job

        raise AdapterNotGoodJobError unless active_job.class.queue_adapter.is_a? GoodJob::Adapter
        raise ActionForStateMismatchError unless status == :discarded

        # Update the executions count because the previous execution will not have been preserved
        # Do not update `exception_executions` because that comes from rescue_from's arguments
        active_job.executions = (active_job.executions || 0) + 1

        new_active_job = nil
        GoodJob::CurrentThread.within do |current_thread|
          current_thread.execution = execution

          execution.class.transaction(joinable: false, requires_new: true) do
            new_active_job = active_job.retry_job(wait: 0, error: error)
            execution.save
          end
        end
        new_active_job
      end
    end

    # Discard a job so that it will not be executed further.
    # This action will add a {DiscardJobError} to the job's {Execution} and mark it as finished.
    # @return [void]
    def discard_job(message)
      with_advisory_lock do
        raise ActionForStateMismatchError unless status.in? [:scheduled, :queued, :retried]

        execution = head_execution(reload: true)
        active_job = execution.active_job

        job_error = GoodJob::ActiveJobJob::DiscardJobError.new(message)

        update_execution = proc do
          execution.update(
            finished_at: Time.current,
            error: [job_error.class, GoodJob::Execution::ERROR_MESSAGE_SEPARATOR, job_error.message].join
          )
        end

        if active_job.respond_to?(:instrument)
          active_job.send :instrument, :discard, error: job_error, &update_execution
        else
          update_execution.call
        end
      end
    end

    # Reschedule a scheduled job so that it executes immediately (or later) by the next available execution thread.
    # @param scheduled_at [DateTime, Time] When to reschedule the job
    # @return [void]
    def reschedule_job(scheduled_at = Time.current)
      with_advisory_lock do
        raise ActionForStateMismatchError unless status.in? [:scheduled, :queued, :retried]

        execution = head_execution(reload: true)
        execution.update(scheduled_at: scheduled_at)
      end
    end

    # Utility method to determine which execution record is used to represent this job
    # @return [String]
    def _execution_id
      attributes['id']
    end

    # Utility method to test whether this job's underlying attributes represents its most recent execution.
    # @return [Boolean]
    def _head?
      _execution_id == head_execution(reload: true).id
    end
  end
end
