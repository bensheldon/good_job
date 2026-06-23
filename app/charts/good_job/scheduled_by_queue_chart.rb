# frozen_string_literal: true

module GoodJob
  class ScheduledByQueueChart < BaseChart
    def initialize(filter)
      super(filter.params)
      @filter = filter
    end

    def data
      binds = time_series_binds
      start_time, end_time = binds.first(2).map(&:value)
      bucket_sql = time_series_bucket_sql("scheduled_at")

      pushdown = <<~SQL.squish
        "good_jobs"."scheduled_at" >= ?::timestamp
        AND "good_jobs"."scheduled_at" < ?::timestamp + ?::integer * INTERVAL '1 second'
      SQL

      inner_sql = @filter.filtered_query
                         .except(:select, :order)
                         .where(pushdown, start_time, end_time, chart_interval_seconds)
                         .select(:queue_name, :scheduled_at)
                         .to_sql

      count_query = <<~SQL.squish
        SELECT *
        FROM generate_series(
          $1::timestamp,
          $2::timestamp,
          $3::integer * INTERVAL '1 second'
        ) timestamp
        LEFT JOIN (
          SELECT
              #{bucket_sql} AS scheduled_at,
              queue_name,
              count(*) AS count
            FROM (#{inner_sql}) sources
            GROUP BY #{bucket_sql}, queue_name
        ) sources ON sources.scheduled_at = timestamp
        ORDER BY timestamp ASC
      SQL

      executions_data = GoodJob::Job.connection_pool.with_connection { |conn| conn.exec_query(GoodJob::Job.pg_or_jdbc_query(count_query), "GoodJob Dashboard Chart", binds) }

      queue_names = executions_data.reject { |d| d['count'].nil? }.map { |d| d['queue_name'] || BaseFilter::EMPTY }.uniq
      labels = []
      timestamps = []
      queues_data = executions_data.to_a.group_by { |d| d['timestamp'] }.each_with_object({}) do |(timestamp, values), hash|
        labels << chart_timestamp_label(timestamp)
        timestamps << timestamp.in_time_zone.iso8601
        queue_names.each do |queue_name|
          (hash[queue_name] ||= []) << values.find { |d| d['queue_name'] == queue_name }&.[]('count')
        end
      end

      {
        type: "line",
        data: {
          labels: labels,
          datasets: queues_data.map do |queue, data|
            label = queue || '(none)'
            {
              label: label,
              data: data,
              backgroundColor: string_to_hsl(label),
              borderColor: string_to_hsl(label),
            }
          end,
        },
        options: {
          scales: {
            y: {
              beginAtZero: true,
            },
          },
        },
        goodJob: chart_metadata(timestamps),
      }
    end
  end
end
