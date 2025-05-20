# frozen_string_literal: true

module GoodJob
  class ScheduledByQueueChart < BaseChart
    def initialize(filter)
      super()
      @filter = filter
    end

    def data
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
            FROM (
              #{@filter.filtered_query.except(:select, :order).select(:queue_name, :scheduled_at).to_sql}
            ) sources
            GROUP BY date_trunc('hour', scheduled_at), queue_name
        ) sources ON sources.scheduled_at = timestamp
        ORDER BY timestamp ASC
      SQL

      executions_data = GoodJob::Job.connection.exec_query(GoodJob::Job.pg_or_jdbc_query(count_query), "GoodJob Dashboard Chart", start_end_binds)

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
