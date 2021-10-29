# frozen_string_literal: true
module GoodJob
  class BaseFilter
    DEFAULT_LIMIT = 25

    attr_accessor :params, :base_query

    def initialize(params, base_query = nil)
      @params = params
      @base_query = base_query || default_base_query
    end

    def records
      after_scheduled_at = params[:after_scheduled_at].present? ? Time.zone.parse(params[:after_scheduled_at]) : nil

      filtered_query.display_all(
        after_scheduled_at: after_scheduled_at,
        after_id: params[:after_id]
      ).limit(params.fetch(:limit, DEFAULT_LIMIT))
    end

    def last
      @_last ||= records.last
    end

    def job_classes
      base_query.group("serialized_params->>'job_class'").count
                .sort_by { |name, _count| name.to_s }
                .to_h
    end

    def queues
      base_query.group(:queue_name).count
                .sort_by { |name, _count| name.to_s }
                .to_h
    end

    def states
      raise NotImplementedError
    end

    def to_params(override)
      {
        job_class: params[:job_class],
        limit: params[:limit],
        queue_name: params[:queue_name],
        state: params[:state],
      }.merge(override).delete_if { |_, v| v.nil? }
    end

    def chart_data
      count_query = Arel.sql(GoodJob::Execution.pg_or_jdbc_query(<<~SQL.squish))
        SELECT *
        FROM generate_series(
          date_trunc('hour', $1::timestamp),
          date_trunc('hour', $2::timestamp),
          '1 hour'
        ) timestamp
        LEFT JOIN (
          SELECT
              date_trunc('hour', scheduled_at) AS scheduled_at,
              queue_name,
              count(*) AS count
            FROM (
              #{filtered_query.except(:select).select('queue_name', 'COALESCE(good_jobs.scheduled_at, good_jobs.created_at)::timestamp AS scheduled_at').to_sql}
            ) sources
            GROUP BY date_trunc('hour', scheduled_at), queue_name
        ) sources ON sources.scheduled_at = timestamp
        ORDER BY timestamp ASC
      SQL

      current_time = Time.current
      binds = [[nil, current_time - 1.day], [nil, current_time]]
      executions_data = GoodJob::Execution.connection.exec_query(count_query, "GoodJob Dashboard Chart", binds)

      queue_names = executions_data.map { |d| d['queue_name'] }.uniq
      labels = []
      queues_data = executions_data.to_a.group_by { |d| d['timestamp'] }.each_with_object({}) do |(timestamp, values), hash|
        labels << timestamp.in_time_zone.strftime('%H:%M %z')
        queue_names.each do |queue_name|
          (hash[queue_name] ||= []) << values.find { |d| d['queue_name'] == queue_name }&.[]('count')
        end
      end

      {
        labels: labels,
        series: queues_data.map do |queue, data|
          {
            name: queue,
            data: data,
          }
        end,
      }
    end

    private

    def default_base_query
      raise NotImplementedError
    end

    def filtered_query
      raise NotImplementedError
    end
  end
end
