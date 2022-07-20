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

    def filtered_query
      query = base_query.includes(:executions).includes_advisory_locks

      query = query.job_class(params[:job_class]) if params[:job_class].present?
      query = query.where(queue_name: params[:queue_name]) if params[:queue_name].present?
      query = query.search_text(params[:query]) if params[:query].present?
      query = query.where(cron_key: params[:cron_key]) if params[:cron_key].present?

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
          query = query.running.select("#{GoodJob::Job.table_name}.*", 'pg_locks.locktype')
        when 'queued'
          query = query.queued
        end
      end

      query
    end

    def filtered_count
      filtered_query.unscope(:select).count
    end

    private

    def default_base_query
      GoodJob::Job.all
    end
  end
end
