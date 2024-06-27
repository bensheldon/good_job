# frozen_string_literal: true

module GoodJob
  # Active Record model that represents an +ActiveJob+ job.
  # Most behavior is currently in BaseExecution in anticipation of
  # moving behavior into +GoodJob::Job+.
  class Execution < BaseExecution
    self.table_name = 'good_jobs'

    belongs_to :job, class_name: 'GoodJob::Job', foreign_key: 'active_job_id', primary_key: 'active_job_id', optional: true, inverse_of: :executions
  end
end
