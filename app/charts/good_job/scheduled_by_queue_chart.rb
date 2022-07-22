# frozen_string_literal: true

module GoodJob
  class ScheduledByQueueChart
    def initialize(filter)
      @filter = filter
    end

    def data
      end_time = Time.current
      start_time = end_time - 1.day

      count_query = Arel.sql(GoodJob::Execution.pg_or_jdbc_query(<<~SQL.squish))
        SELECT
          timestamp,
          scheduled_executions,
          completed_executions,
          retried_executions,
          discarded_executions
        FROM generate_series(
          date_trunc('hour', $1::timestamp),
          date_trunc('hour', $2::timestamp),
          '1 hour'
        ) timestamp
        LEFT JOIN (
          SELECT
              date_trunc('hour', scheduled_at) AS scheduled_at,
              COUNT(*) AS scheduled_executions
            FROM (
              #{@filter.filtered_query
                       .except(:select, :order)
                       .unscope(where: :retried_good_job_id)
                       .select("MIN(COALESCE(scheduled_at, created_at))::timestamp AS scheduled_at")
                       .group(:active_job_id)
                       .to_sql}
            ) sources
            GROUP BY date_trunc('hour', scheduled_at)
        ) scheduled_executions ON scheduled_executions.scheduled_at = timestamp
        LEFT JOIN (
          SELECT
              date_trunc('hour', finished_at) AS finished_at,
              COUNT(*) FILTER (WHERE error IS NULL) AS completed_executions,
              COUNT(*) FILTER (WHERE error IS NOT NULL AND retried_good_job_id IS NOT NULL) AS retried_executions,
              COUNT(*) FILTER (WHERE error IS NOT NULL AND retried_good_job_id IS NULL) AS discarded_executions
            FROM (
              #{@filter.filtered_query
                       .except(:select, :order)
                       .where.not(finished_at: nil)
                       .select('finished_at', 'error', 'retried_good_job_id')
                       .to_sql}
            ) sources
            GROUP BY date_trunc('hour', finished_at)
        ) finished_executions ON finished_executions.finished_at = timestamp
        ORDER BY timestamp ASC
      SQL

      binds = [
        ActiveRecord::Relation::QueryAttribute.new('start_time', start_time, ActiveRecord::Type::DateTime.new),
        ActiveRecord::Relation::QueryAttribute.new('end_time', end_time, ActiveRecord::Type::DateTime.new),
      ]
      executions_data = GoodJob::Execution.connection.exec_query(GoodJob::Execution.pg_or_jdbc_query(count_query), "GoodJob Dashboard Chart", binds)

      puts executions_data

      labels = executions_data.map { |row| row['timestamp'].in_time_zone.strftime('%H:%M') }

      colors = {
        scheduled: "blue",
        succeeded: "#198754",
        retried: "orange",
        discarded: "#FF0000",
      }

      {
        labels: labels,
        datasets: [
          {
            label: 'Scheduled/Enqueued',
            data: executions_data.map { |row| row['scheduled_executions'] || 0 },
            type: 'line',
            borderColor: colors[:scheduled],
          },
          # {
          #   label: 'Retried',
          #   data: executions_data.map { |row| row['retried_executions'] || 0 },
          #   stack: 1,
          #   type: 'bar',
          #   backgroundColor: colors[:retried],
          # },
          {
            label: 'Finished',
            data: executions_data.map { |row| row['completed_executions'] || 0 },
            stack: 1,
            type: 'bar',
            backgroundColor: colors[:succeeded],
          },
          {
            label: 'Discarded',
            data: executions_data.map { |row| row['discarded_executions'] || 0 },
            stack: 1,
            type: 'bar',
            backgroundColor: colors[:discarded],
          },
        ],
      }
    end

    def string_to_hsl(string)
      hash_value = string.sum

      hue = hash_value % 360
      saturation = (hash_value % 50) + 50
      lightness = '50'

      "hsl(#{hue}, #{saturation}%, #{lightness}%)"
    end
  end
end
