# frozen_string_literal: true

module GoodJob
  class JobsFilter < BaseFilter
    def states
      @_states ||= begin
        query = filtered_query(params.except(:state))
        {
          'scheduled' =>  query.scheduled.count,
          'retried' => query.retried.count,
          'queued' => query.queued.count,
          'running' => query.running.count,
          'succeeded' => query.succeeded.count,
          'discarded' => query.discarded.count,
        }
      end
    end

    def filtered_query(filter_params = params)
      query = base_query

      query = query.job_class(filter_params[:job_class]) if filter_params[:job_class].present?
      query = query.where(queue_name: filter_params[:queue_name]) if filter_params[:queue_name].present?
      query = query.search_text(filter_params[:query]) if filter_params[:query].present?
      query = query.where(cron_key: filter_params[:cron_key]) if filter_params[:cron_key].present?

      if filter_params[:state]
        case filter_params[:state]
        when 'discarded'
          query = query.discarded
        when 'succeeded'
          query = query.succeeded
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
      @_filtered_count ||= filtered_query.unscope(:select).count
    end

    private

    def query_for_records
      filtered_query.includes_advisory_locks
    end

    def default_base_query
      GoodJob::Job.all
    end
  end
end
