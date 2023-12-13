# frozen_string_literal: true

module GoodJob
  # Active Record model that represents an +ActiveJob+ job.
  # There is not a table in the database whose discrete rows represents "Jobs".
  # The +good_jobs+ table is a table of individual {GoodJob::Execution}s that share the same +active_job_id+.
  # A single row from the +good_jobs+ table of executions is fetched to represent a Job.
  #
  class Job < BaseExecution
    # Raised when an inappropriate action is applied to a Job based on its state.
    ActionForStateMismatchError = Class.new(StandardError)
    # Raised when GoodJob is not configured as the Active Job Queue Adapter
    AdapterNotGoodJobError = Class.new(StandardError)
    # Attached to a Job's Execution when the Job is discarded.
    DiscardJobError = Class.new(StandardError)

    class << self
      delegate :table_name, to: GoodJob::Execution

      def table_name=(_value)
        raise NotImplementedError, 'Assign GoodJob::Execution.table_name directly'
      end
    end

    self.primary_key = 'active_job_id'
    self.advisory_lockable_column = 'active_job_id'

    belongs_to :batch, class_name: 'GoodJob::BatchRecord', inverse_of: :jobs, optional: true
    has_many :executions, -> { order(created_at: :asc) }, class_name: 'GoodJob::Execution', foreign_key: 'active_job_id', inverse_of: :job # rubocop:disable Rails/HasManyOrHasOneDependent
    has_many :discrete_executions, -> { order(created_at: :asc) }, class_name: 'GoodJob::DiscreteExecution', foreign_key: 'active_job_id', primary_key: :active_job_id, inverse_of: :job # rubocop:disable Rails/HasManyOrHasOneDependent

    after_destroy lambda {
      GoodJob::DiscreteExecution.where(active_job_id: active_job_id).delete_all if discrete? # TODO: move into association `dependent: :delete_all` after v4
    }

    # Only the most-recent unretried execution represents a "Job"
    default_scope { where(retried_good_job_id: nil) }

    # Get Jobs finished before the given timestamp.
    # @!method finished_before(timestamp)
    # @!scope class
    # @param timestamp (DateTime, Time)
    # @return [ActiveRecord::Relation]
    scope :finished_before, ->(timestamp) { where(arel_table['finished_at'].lteq(timestamp)) }

    # First execution will run in the future
    scope :scheduled, -> { where(finished_at: nil).where(coalesce_scheduled_at_created_at.gt(DateTime.current)).where(params_execution_count.lt(2)) }
    # Execution errored, will run in the future
    scope :retried, -> { where(finished_at: nil).where(coalesce_scheduled_at_created_at.gt(DateTime.current)).where(params_execution_count.gt(1)) }
    # Immediate/Scheduled time to run has passed, waiting for an available thread run
    scope :queued, -> { where(finished_at: nil).where(coalesce_scheduled_at_created_at.lteq(DateTime.current)).joins_advisory_locks.where(pg_locks: { locktype: nil }) }
    # Advisory locked and executing
    scope :running, -> { where(finished_at: nil).joins_advisory_locks.where.not(pg_locks: { locktype: nil }) }
    # Finished executing (succeeded or discarded)
    scope :finished, -> { where.not(finished_at: nil).where(retried_good_job_id: nil) }
    # Completed executing successfully
    scope :succeeded, -> { finished.where(error: nil) }
    # Errored but will not be retried
    scope :discarded, -> { finished.where.not(error: nil) }

    scope :unfinished_undiscrete, -> { where(finished_at: nil, retried_good_job_id: nil, is_discrete: [nil, false]) }

    # The job's Active Job UUID
    # @return [String]
    def id
      active_job_id
    end

    # Override #reload to add a custom scope to ensure the reloaded record is the head execution
    # @return [Job]
    def reload(options = nil)
      self.class.connection.clear_query_cache

      # override with the `where(retried_good_job_id: nil)` scope
      override_query = self.class.where(retried_good_job_id: nil)
      fresh_object =
        if options && options[:lock]
          self.class.unscoped { override_query.lock(options[:lock]).find(id) }
        else
          self.class.unscoped { override_query.find(id) }
        end

      @attributes = fresh_object.instance_variable_get(:@attributes)
      @new_record = false
      @previously_new_record = false
      self
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

    # The number of times this job has been executed, according to Active Job's serialized state.
    # @return [Numeric]
    def executions_count
      aj_count = serialized_params.fetch('executions', 0)
      # The execution count within serialized_params is not updated
      # once the underlying execution has been executed.
      if status.in? [:discarded, :succeeded, :running]
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
      error || executions[-2]&.error
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
      finished_at.present? && retried_good_job_id.nil?
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
      with_advisory_lock do
        execution = head_execution(reload: true)
        active_job = execution.active_job

        raise AdapterNotGoodJobError unless active_job.class.queue_adapter.is_a? GoodJob::Adapter
        raise ActionForStateMismatchError if execution.finished_at.blank? || execution.error.blank?

        # Update the executions count because the previous execution will not have been preserved
        # Do not update `exception_executions` because that comes from rescue_from's arguments
        active_job.executions = (active_job.executions || 0) + 1

        new_active_job = nil
        GoodJob::CurrentThread.within do |current_thread|
          current_thread.execution = execution

          execution.class.transaction(joinable: false, requires_new: true) do
            new_active_job = active_job.retry_job(wait: 0, error: execution.error)
            execution.error_event = ERROR_EVENT_RETRIED if execution.error && execution.class.error_event_migrated?
            execution.save!
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
        execution = head_execution(reload: true)

        raise ActionForStateMismatchError if execution.finished_at.present?

        execution.update(scheduled_at: scheduled_at)
      end
    end

    # Destroy all of a discarded or finished job's executions from the database so that it will no longer appear on the dashboard.
    # @return [void]
    def destroy_job
      with_advisory_lock do
        execution = head_execution(reload: true)

        raise ActionForStateMismatchError if execution.finished_at.blank?

        destroy
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

    private

    def _discard_job(message)
      execution = head_execution(reload: true)
      active_job = execution.active_job(ignore_deserialization_errors: true)

      raise ActionForStateMismatchError if execution.finished_at.present?

      job_error = GoodJob::Job::DiscardJobError.new(message)

      update_execution = proc do
        execution.update(
          {
            finished_at: Time.current,
            error: GoodJob::Execution.format_error(job_error),
          }.tap do |attrs|
            attrs[:error_event] = ERROR_EVENT_DISCARDED if self.class.error_event_migrated?
          end
        )
      end

      if active_job.respond_to?(:instrument)
        active_job.send :instrument, :discard, error: job_error, &update_execution
      else
        update_execution.call
      end
    end
  end
end
