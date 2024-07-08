# frozen_string_literal: true

module GoodJob
  # Active Record model that represents an +ActiveJob+ job.
  class Job < BaseExecution
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

    belongs_to :batch, class_name: 'GoodJob::BatchRecord', inverse_of: :jobs, optional: true
    belongs_to :locked_by_process, class_name: "GoodJob::Process", foreign_key: :locked_by_id, inverse_of: :locked_jobs, optional: true
    has_many :executions, -> { order(created_at: :asc) }, class_name: 'GoodJob::Execution', foreign_key: 'active_job_id', primary_key: :active_job_id, inverse_of: :job, dependent: :delete_all
    # TODO: rename callers of discrete_execution to executions, but after v4 has some time to bake for cleaner diffs/patches
    has_many :discrete_executions, -> { order(created_at: :asc) }, class_name: 'GoodJob::Execution', foreign_key: 'active_job_id', primary_key: :active_job_id, inverse_of: :job, dependent: :delete_all

    before_create -> { self.id = active_job_id }, if: -> { active_job_id.present? }

    # Get Jobs finished before the given timestamp.
    # @!method finished_before(timestamp)
    # @!scope class
    # @param timestamp (DateTime, Time)
    # @return [ActiveRecord::Relation]
    scope :finished_before, ->(timestamp) { where(arel_table['finished_at'].lteq(bind_value('finished_at', timestamp, ActiveRecord::Type::DateTime))) }

    # First execution will run in the future
    scope :scheduled, -> { where(finished_at: nil).where(coalesce_scheduled_at_created_at.gt(bind_value('coalesce', Time.current, ActiveRecord::Type::DateTime))).where(params_execution_count.lt(2)) }
    # Execution errored, will run in the future
    scope :retried, -> { where(finished_at: nil).where(coalesce_scheduled_at_created_at.gt(bind_value('coalesce', Time.current, ActiveRecord::Type::DateTime))).where(params_execution_count.gt(1)) }
    # Immediate/Scheduled time to run has passed, waiting for an available thread run
    scope :queued, -> { where(finished_at: nil).where(coalesce_scheduled_at_created_at.lteq(bind_value('coalesce', Time.current, ActiveRecord::Type::DateTime))).joins_advisory_locks.where(pg_locks: { locktype: nil }) }
    # Advisory locked and executing
    scope :running, -> { where(finished_at: nil).joins_advisory_locks.where.not(pg_locks: { locktype: nil }) }
    # Finished executing (succeeded or discarded)
    scope :finished, -> { where.not(finished_at: nil).where(retried_good_job_id: nil) }
    # Completed executing successfully
    scope :succeeded, -> { finished.where(error: nil) }
    # Errored but will not be retried
    scope :discarded, -> { finished.where.not(error: nil) }

    # TODO: it would be nice to enforce these values at the model
    # validates :active_job_id, presence: true
    # validates :scheduled_at, presence: true
    # validates :job_class, presence: true
    # validates :error_event, presence: true, if: -> { error.present? }

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
        GoodJob::CurrentThread.within do |current_thread|
          current_thread.job = self
          current_thread.retry_now = true

          self.class.transaction(joinable: false, requires_new: true) do
            new_active_job = active_job.retry_job(wait: 0, error: error)
            self.error_event = ERROR_EVENT_RETRIED if error
            save!
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

    # Utility method to determine which execution record is used to represent this job
    # @return [String]
    def _execution_id
      attributes['id']
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
          error_event: ERROR_EVENT_DISCARDED
        )
      end

      if active_job.respond_to?(:instrument)
        active_job.send :instrument, :discard, error: job_error, &update_record
      else
        update_record.call
      end
    end
  end
end
