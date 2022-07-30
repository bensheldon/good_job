# frozen_string_literal: true
module GoodJob
  class PerformanceFilter < BaseFilter
    DURATIONS = {
      "2m" => '1 second',
      "2h" => '1 minute',
      "24h" => '10 minutes',
      "3d" => '1 hour',
      "7d" => '2 hours',
      "14d" => '4 hours',
      "30d" => '12 hours',
      "90d" => '1 day',
    }.freeze

    def states
      {
        'scheduled' => base_query.scheduled.count,
        'queued' => base_query.queued.count,
        'running' => base_query.running.count,
        'succeeded' => base_query.succeeded.count,
        'errored' => base_query.errored.count,
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

    def default_base_query
      GoodJob::Execution.all
    end
  end
end
