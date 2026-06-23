# frozen_string_literal: true

module GoodJob
  class PerformanceIndexChart < BaseChart
    def data
      binds = time_series_binds
      start_time, end_time = binds.first(2).map(&:value)
      bucket_sql = time_series_bucket_sql(:scheduled_at)

      pushdown = <<~SQL.squish
        scheduled_at >= ?::timestamp
        AND scheduled_at < ?::timestamp + ?::integer * INTERVAL '1 second'
      SQL

      inner_sql = GoodJob::Execution.where(pushdown, start_time, end_time, chart_interval_seconds)
                                    .select(:job_class, :scheduled_at, :duration)
                                    .to_sql

      sum_query = <<~SQL.squish
        SELECT *
        FROM generate_series(
          $1::timestamp,
          $2::timestamp,
          $3::integer * INTERVAL '1 second'
        ) timestamp
        LEFT JOIN (
          SELECT
              #{bucket_sql} AS scheduled_at,
              job_class,
              SUM(duration) AS sum
            FROM (#{inner_sql}) sources
            GROUP BY #{bucket_sql}, job_class
        ) sources ON sources.scheduled_at = timestamp
        ORDER BY timestamp ASC
      SQL

      executions_data = GoodJob::Job.connection_pool.with_connection { |conn| conn.exec_query(GoodJob::Job.pg_or_jdbc_query(sum_query), "GoodJob Performance Chart", binds) }

      job_names = executions_data.reject { |d| d['sum'].nil? }.map { |d| d['job_class'] || BaseFilter::EMPTY }.uniq
      labels = []
      timestamps = []
      jobs_data = executions_data.to_a.group_by { |d| d['timestamp'] }.each_with_object({}) do |(timestamp, values), hash|
        labels << chart_timestamp_label(timestamp)
        timestamps << timestamp.in_time_zone.iso8601
        job_names.each do |job_class|
          sum = values.find { |d| d['job_class'] == job_class }&.[]('sum')
          duration = sum ? ActiveSupport::Duration.parse(sum).to_f : 0
          (hash[job_class] ||= []) << duration
        end
      end

      {
        type: "line",
        data: {
          labels: labels,
          datasets: jobs_data.map do |job_class, data|
            label = job_class || '(none)'
            {
              label: label,
              data: data,
              backgroundColor: string_to_hsl(label),
              borderColor: string_to_hsl(label),
            }
          end,
        },
        options: {
          plugins: {
            title: {
              display: true,
              text: I18n.t("good_job.performance.index.chart_title"),
            },
            legend: {
              vertical: true,
            },
          },
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
