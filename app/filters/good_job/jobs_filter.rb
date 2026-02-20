# frozen_string_literal: true

module GoodJob
  class JobsFilter < BaseFilter
    UUID_REGEX = /\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i

    def state_names
      %w[scheduled retried queued running succeeded discarded]
    end

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
      base_query
        .merge(filter_by_job_class(filter_params[:job_class]))
        .merge(filter_by_queue_name(filter_params[:queue_name]))
        .merge(filter_by_search_query(filter_params[:query]))
        .merge(filter_by_cron_key(filter_params[:cron_key]))
        .merge(filter_by_finished_since(filter_params[:finished_since]))
        .merge(filter_by_state(filter_params[:state]))
    end

    def filtered_count
      @_filtered_count ||= filtered_query.unscope(:select).count
    end

    def ordered_by
      case params[:state]
      when "scheduled", "retried", "pending", "queued"
        %w[scheduled_at asc]
      when "running"
        %w[performed_at desc]
      when "finished", "discarded"
        %w[finished_at desc]
      else
        %w[created_at desc]
      end
    end

    private

    def filter_by_job_class(job_class)
      return {} if job_class.blank?

      GoodJob::Job.job_class(job_class)
    end

    def filter_by_queue_name(queue_name)
      return {} if queue_name.blank?

      GoodJob::Job.where(queue_name: queue_name)
    end

    def filter_by_search_query(query)
      search_query = query&.strip
      return {} if search_query.blank?

      if query_is_uuid_and_job_exists?(search_query)
        GoodJob::Job.where(active_job_id: search_query)
      else
        GoodJob::Job.search_text(search_query)
      end
    end

    def filter_by_cron_key(cron_key)
      return {} if cron_key.blank?

      GoodJob::Job.where(cron_key: cron_key)
    end

    def filter_by_finished_since(since)
      return {} if since.blank?

      GoodJob::Job.where(finished_at: finished_since(since)..)
    end

    def filter_by_state(state)
      case state
      when 'discarded' then GoodJob::Job.discarded
      when 'succeeded' then GoodJob::Job.succeeded
      when 'retried'   then GoodJob::Job.retried
      when 'scheduled' then GoodJob::Job.scheduled
      when 'running'   then GoodJob::Job.running
      when 'queued'    then GoodJob::Job.queued
      else {}
      end
    end

    def query_for_records
      filtered_query
    end

    def default_base_query
      GoodJob::Job.all
    end

    def finished_since(finished_since)
      case finished_since
      when '1_hour_ago'
        1.hour.ago
      when '3_hours_ago'
        3.hours.ago
      when '24_hours_ago'
        24.hours.ago
      when '3_days_ago'
        3.days.ago
      when '7_days_ago'
        7.days.ago
      end
    end

    def query_is_uuid_and_job_exists?(search_query)
      @_query_is_uuid_and_job_exists ||= search_query&.match?(UUID_REGEX) && base_query.exists?(active_job_id: search_query)
    end
  end
end
