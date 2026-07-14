# frozen_string_literal: true

module GoodJob
  class ScheduledByQueueChart < BaseChart
    def initialize(filter)
      super()
      @filter = filter
    end

    def data
      binds = start_end_binds
      start_time, end_time = binds.map(&:value)

      # Align the inner range predicate to the same hour buckets the outer generate_series
      # produces. Doing the truncation in SQL (rather than in Ruby with beginning_of_hour)
      # keeps both sides on the same grid even when the app's time zone has a fractional
      # offset from UTC (e.g. IST +05:30). AR serializes Time binds as UTC, so the outer
      # date_trunc operates in UTC, and this predicate must match that.
      pushdown = <<~SQL.squish
        "good_jobs"."scheduled_at" >= date_trunc('hour', ?::timestamp)
        AND "good_jobs"."scheduled_at" < date_trunc('hour', ?::timestamp) + interval '1 hour'
      SQL

      inner_sql = @filter.filtered_query
                         .except(:select, :order)
                         .where(pushdown, start_time, end_time)
                         .select(:queue_name, :scheduled_at)
                         .to_sql

      count_query = <<~SQL.squish
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
            FROM (#{inner_sql}) sources
            GROUP BY date_trunc('hour', scheduled_at), queue_name
        ) sources ON sources.scheduled_at = timestamp
        ORDER BY timestamp ASC
      SQL

      executions_data = GoodJob::Job.connection_pool.with_connection { |conn| conn.exec_query(GoodJob::Job.pg_or_jdbc_query(count_query), "GoodJob Dashboard Chart", binds) }

      queue_names = executions_data.reject { |d| d['count'].nil? }.map { |d| d['queue_name'] || BaseFilter::EMPTY }.uniq
      labels = []
      queues_data = executions_data.to_a.group_by { |d| d['timestamp'] }.each_with_object({}) do |(timestamp, values), hash|
        labels << timestamp.in_time_zone.strftime('%H:%M')
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
      }
    end
  end
end
