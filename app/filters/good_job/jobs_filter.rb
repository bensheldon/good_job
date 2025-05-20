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
      query = base_query

      query = query.job_class(filter_params[:job_class]) if filter_params[:job_class].present?
      query = query.where(queue_name: filter_params[:queue_name]) if filter_params[:queue_name].present?

      search_query = filter_params[:query]&.strip
      if search_query.present?
        query = if query_is_uuid_and_job_exists?(search_query)
                  query.where(active_job_id: search_query)
                else
                  query.search_text(search_query)
                end
      end

      query = query.where(cron_key: filter_params[:cron_key]) if filter_params[:cron_key].present?
      query = query.where(finished_at: finished_since(filter_params[:finished_since])..) if filter_params[:finished_since].present?

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
          query = query.running
        when 'queued'
          query = query.queued
        end
      end

      query
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
