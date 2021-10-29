# frozen_string_literal: true
module GoodJob
  class JobsFilter < BaseFilter
    def states
      {
        'scheduled' =>  base_query.scheduled.count,
        'retried' => base_query.retried.count,
        'queued' => base_query.queued.count,
        'running' => base_query.running.count,
        'finished' => base_query.finished.count,
        'discarded' => base_query.discarded.count,
      }
    end

    private

    def default_base_query
      GoodJob::ActiveJobJob.all
    end

    def filtered_query
      query = base_query.includes(:executions)
                        .joins_advisory_locks.select('good_jobs.*', 'pg_locks.locktype AS locktype')

      query = query.job_class(params[:job_class]) if params[:job_class]
      query = query.where(queue_name: params[:queue_name]) if params[:queue_name]

      if params[:state]
        case params[:state]
        when 'discarded'
          query = query.discarded
        when 'finished'
          query = query.finished
        when 'retried'
          query = query.retried
        when 'scheduled'
          query = query.scheduled
        when 'running'
          query = query.running.select('good_jobs.*', 'pg_locks.locktype')
        when 'queued'
          query = query.queued
        end
      end

      query
    end
  end
end
