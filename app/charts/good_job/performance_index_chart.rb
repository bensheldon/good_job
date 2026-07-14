# frozen_string_literal: true

module GoodJob
  class PerformanceIndexChart < BaseChart
    def initialize(range = GoodJob::PerformanceRange.new)
      super()
      @range = range
    end

    def data
      binds = @range.time_series_binds
      bucket_sql = @range.time_series_bucket_sql("scheduled_at")
      inner_sql = @range.apply(GoodJob::Execution).select(:job_class, :scheduled_at, :duration).to_sql

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
        labels << @range.chart_timestamp_label(timestamp)
        timestamps << @range.canonical_timestamp(timestamp)
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
        goodJob: {
          interval_seconds: @range.interval_seconds,
          range_end: @range.canonical_timestamp(@range.end_time),
          range_start: @range.canonical_timestamp(@range.start_time),
          time_series: true,
          timestamps: timestamps,
        },
      }
    end
  end
end
