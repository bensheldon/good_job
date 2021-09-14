# frozen_string_literal: true
module GoodJob
  # ActiveRecord model that represents an +ActiveJob+ job.
  # Is the same record data as a {GoodJob::Execution} but only the most recent execution.
  # Parent class can be configured with +GoodJob.active_record_parent_class+.
  # @!parse
  #   class ActiveJob < ActiveRecord::Base; end
  class ActiveJobJob < Object.const_get(GoodJob.active_record_parent_class)
    include GoodJob::Lockable

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

    # Get Jobs in display order with optional keyset pagination.
    # @!method display_all(after_scheduled_at: nil, after_id: nil)
    # @!scope class
    # @param after_scheduled_at [DateTime, String, nil]
    #   Display records scheduled after this time for keyset pagination
    # @param after_id [Numeric, String, nil]
    #   Display records after this ID for keyset pagination
    # @return [ActiveRecord::Relation]
    scope :display_all, (lambda do |after_scheduled_at: nil, after_id: nil|
      query = order(Arel.sql('COALESCE(scheduled_at, created_at) DESC, id DESC'))
      if after_scheduled_at.present? && after_id.present?
        query = query.where(Arel.sql('(COALESCE(scheduled_at, created_at), id) < (:after_scheduled_at, :after_id)'), after_scheduled_at: after_scheduled_at, after_id: after_id)
      elsif after_scheduled_at.present?
        query = query.where(Arel.sql('(COALESCE(scheduled_at, created_at)) < (:after_scheduled_at)'), after_scheduled_at: after_scheduled_at)
      end
      query
    end)

    def id
      active_job_id
    end

    def _execution_id
      attributes['id']
    end

    def job_class
      serialized_params['job_class']
    end

    def status
      if finished_at.present?
        if error.present?
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

    def head_execution
      executions.last
    end

    def tail_execution
      executions.first
    end

    def executions_count
      aj_count = serialized_params.fetch('executions', 0)
      # The execution count within serialized_params is not updated
      # once the underlying execution has been executed.
      if status.in? [:discarded, :finished, :running]
        aj_count + 1
      else
        aj_count
      end
    end

    def preserved_executions_count
      executions.size
    end

    def recent_error
      error.presence || executions[-2]&.error
    end

    def running?
      # Avoid N+1 Query: `.joins_advisory_locks.select('good_jobs.*', 'pg_locks.locktype AS locktype')`
      if has_attribute?(:locktype)
        self['locktype'].present?
      else
        advisory_locked?
      end
    end
  end
end
