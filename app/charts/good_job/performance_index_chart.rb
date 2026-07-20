# frozen_string_literal: true

module GoodJob
  class PerformanceIndexChart < BaseChart
    def data
      table_name = GoodJob::Execution.table_name

      sum_query = <<~SQL.squish
        SELECT *
        FROM generate_series(
          date_trunc('hour', $1::timestamp),
          date_trunc('hour', $2::timestamp),
          '1 hour'
        ) timestamp
        LEFT JOIN (
          SELECT
              date_trunc('hour', scheduled_at) AS scheduled_at,
              job_class,
              SUM(duration) AS sum
            FROM #{table_name} sources
            WHERE scheduled_at >= date_trunc('hour', $3::timestamp)
              AND scheduled_at < date_trunc('hour', $4::timestamp) + interval '1 hour'
            GROUP BY date_trunc('hour', scheduled_at), job_class
        ) sources ON sources.scheduled_at = timestamp
        ORDER BY timestamp ASC
      SQL

      # The window binds ($1/$2) are reused for the inner WHERE clause ($3/$4);
      # they must be duplicated because pg_or_jdbc_query rewrites every bind to a
      # positional "?" on JRuby, so placeholders and binds have to match 1:1.
      binds = start_end_binds
      executions_data = GoodJob::Job.connection_pool.with_connection { |conn| conn.exec_query(GoodJob::Job.pg_or_jdbc_query(sum_query), "GoodJob Performance Chart", binds + binds) }

      job_names = executions_data.reject { |d| d['sum'].nil? }.map { |d| d['job_class'] || BaseFilter::EMPTY }.uniq
      labels = []
      jobs_data = executions_data.to_a.group_by { |d| d['timestamp'] }.each_with_object({}) do |(timestamp, values), hash|
        labels << timestamp.in_time_zone.strftime('%H:%M')
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
      }
    end
  end
end
