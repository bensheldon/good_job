# frozen_string_literal: true

module GoodJob # :nodoc:
  class Execution < BaseRecord
    include ErrorEvents

    self.table_name = 'good_job_executions'
    self.implicit_order_column = 'created_at'

    belongs_to :job, class_name: 'GoodJob::Job', foreign_key: 'active_job_id', primary_key: 'id', inverse_of: :executions, optional: true

    scope :finished, -> { where.not(finished_at: nil) }

    alias_attribute :performed_at, :created_at

    # TODO: Remove when support for Rails 6.1 is dropped
    attribute :duration, :interval if ActiveJob.version.canonical_segments.take(2) == [6, 1]

    def number
      serialized_params.fetch('executions', 0) + 1
    end

    # Time between when this job was expected to run and when it started running
    def queue_latency
      created_at - scheduled_at
    end

    # Monotonic time between when this job started and finished
    def runtime_latency
      duration
    end

    def last_status_at
      finished_at || created_at
    end

    def status
      if finished_at.present?
        if error.present? && job.finished_at.present?
          :discarded
        elsif error.present?
          :retried
        else
          :succeeded
        end
      else
        :running
      end
    end

    def display_serialized_params
      serialized_params.merge({
                                _good_job_execution: attributes.except('serialized_params'),
                              })
    end

    def filtered_error_backtrace
      Rails.backtrace_cleaner.clean(error_backtrace || [])
    end
  end
end

ActiveSupport.run_load_hooks(:good_job_execution, GoodJob::Execution)
