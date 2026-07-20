# frozen_string_literal: true

module GoodJob
  class PerformanceIndexChart < BaseChart
    def initialize(range = GoodJob::PerformanceRange.new)
      super()
      @range = range
    end

    def data
      binds = @range.time_series_binds
      bucket_sql = @range.time_series_bucket_sql(
        "scheduled_at",
        start_expression: "range_parameters.series_start_time",
        interval_expression: "range_parameters.interval_seconds"
      )
      inner_sql = @range.apply(GoodJob::Execution).select(:job_class, :scheduled_at, :duration).to_sql

      # Keep each bind placeholder single-use because JDBC binds every converted occurrence.
      sum_query = <<~SQL.squish
        WITH range_parameters AS (
          SELECT
            $1::timestamp AS series_start_time,
            $2::timestamp AS series_end_time,
            $3::bigint AS interval_seconds
        ), timestamps AS (
          SELECT generate_series(
            series_start_time,
            series_end_time,
            interval_seconds * INTERVAL '1 second'
          ) AS timestamp
          FROM range_parameters
        ), sources AS (
          SELECT
            #{bucket_sql} AS scheduled_at,
            job_class,
            SUM(duration) AS sum
          FROM (#{inner_sql}) executions
          CROSS JOIN range_parameters
          GROUP BY #{bucket_sql}, job_class
        )
        SELECT *
        FROM timestamps
        LEFT JOIN sources ON sources.scheduled_at = timestamps.timestamp
        ORDER BY timestamp ASC
      SQL

      executions_data = GoodJob::Job.connection_pool.with_connection { |conn| conn.exec_query(GoodJob::Job.pg_or_jdbc_query(sum_query), "GoodJob Performance Chart", binds) }

      job_names = executions_data.reject { |d| d['sum'].nil? }.map { |d| d['job_class'] || BaseFilter::EMPTY }.uniq
      timestamp_values = []
      timestamps = []
      jobs_data = executions_data.to_a.group_by { |d| d['timestamp'] }.each_with_object({}) do |(timestamp, values), hash|
        timestamp_values << timestamp
        timestamps << @range.canonical_timestamp(timestamp)
        job_names.each do |job_class|
          sum = values.find { |d| d['job_class'] == job_class }&.[]('sum')
          duration = sum ? ActiveSupport::Duration.parse(sum).to_f : 0
          (hash[job_class] ||= []) << duration
        end
      end
      labels = @range.chart_timestamp_labels(timestamp_values)

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
          timestamp_label_style: @range.label_style,
          time_series: true,
          timestamps: timestamps,
        },
      }
    end
  end
end
