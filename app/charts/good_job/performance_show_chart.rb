# frozen_string_literal: true

module GoodJob
  class PerformanceShowChart < BaseChart
    # These numbers are lifted from Sidekiq
    BUCKET_INTERVALS = [
      0.02, 0.03, 0.045, 0.065, 0.1,
      0.15, 0.225, 0.335, 0.5, 0.75,
      1.1, 1.7, 2.5, 3.8, 5.75,
      8.5, 13, 20, 30, 45,
      65, 100, 150, 225, 335,
      10**8 # About 3 years
    ].freeze

    def initialize(job_class)
      super()
      @job_class = job_class
    end

    def data
      table_name = GoodJob::Execution.table_name

      interval_entries = BUCKET_INTERVALS.map { "interval '#{_1}'" }.join(",")
      sum_query = <<~SQL.squish
        SELECT
          WIDTH_BUCKET(duration, ARRAY[#{interval_entries}]) as bucket_index,
          COUNT(WIDTH_BUCKET(duration, ARRAY[#{interval_entries}])) AS count
        FROM #{table_name} sources
        WHERE
          scheduled_at > $1::timestamp
          AND scheduled_at < $2::timestamp
          AND job_class = $3
          AND duration IS NOT NULL
        GROUP BY bucket_index
      SQL

      binds = [
        *start_end_binds,
        @job_class,
      ]
      labels = BUCKET_INTERVALS.map { |interval| GoodJob::ApplicationController.helpers.format_duration(interval) }
      labels[-1] = I18n.t("good_job.performance.show.slow")
      executions_data = GoodJob::Job.connection.exec_query(GoodJob::Job.pg_or_jdbc_query(sum_query), "GoodJob Performance Job Chart", binds)
      executions_data = executions_data.to_a.index_by { |data| data["bucket_index"] }

      bucket_data = 0.upto(BUCKET_INTERVALS.count).map do |bucket_index|
        executions_data.dig(bucket_index, "count") || 0
      end

      {
        type: "bar",
        data: {
          labels: labels,
          datasets: [{
            label: @job_class,
            data: bucket_data,
            backgroundColor: string_to_hsl(@job_class),
            borderColor: string_to_hsl(@job_class),
          }],
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
