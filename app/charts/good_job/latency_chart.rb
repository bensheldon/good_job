# frozen_string_literal: true

module GoodJob
  class LatencyChart
    INTERVALS = {
      second: 2.minutes,
      minute: 2.hours,
      hour: 5.days,
      day: 120.days,
    }.freeze

    CALCULATIONS = {
      min: 'min',
      avg: 'avg',
      p95: 'percentile_95',
      max: 'max',
    }

    attr_reader :interval

    def initialize(filter, interval: :second)
      raise ArgumentError, "interval must be one of #{INTERVALS.keys.join(', ')}" unless interval.in?(INTERVALS.keys)

      @filter = filter
      @interval = interval
    end

    def data
      interval_duration = INTERVALS[interval]

      base_query = GoodJob::Execution.only_scheduled
      # Filter out jobs that have been discarded because they will have been finished but not performed
      base_query = base_query.where("NOT (finished_at IS NOT NULL AND performed_at IS NULL)")

      table_name = GoodJob::Execution.table_name

      end_time = Time.current
      start_time = end_time - interval_duration

      count_query = Arel.sql(GoodJob::Execution.pg_or_jdbc_query(<<~SQL.squish))
        SELECT
          timestamp,
          min,
          percentile_95,
          max,
          COALESCE(count, 0) AS count
        FROM generate_series(
          date_trunc('#{interval}', $1::timestamp),
          date_trunc('#{interval}', $2::timestamp),
          '1 #{interval}'
        ) timestamp
        LEFT JOIN (
          SELECT
              percentile_disc(0.95) WITHIN GROUP (ORDER BY extract('epoch' from performed_at - scheduled_at) ASC) AS percentile_95,
              max(extract('epoch' from performed_at - scheduled_at)) AS max,
              min(extract('epoch' from performed_at - scheduled_at)) AS min,
              date_trunc('#{interval}', performed_at) AS performed_at,
              count(*) AS count
            FROM (
              #{base_query.except(:select, :order).select(
                "COALESCE(#{table_name}.performed_at, '#{end_time}'::timestamp) AS performed_at, COALESCE(#{table_name}.scheduled_at, #{table_name}.created_at)::timestamp AS scheduled_at"
              ).to_sql}
            ) sources
            GROUP BY date_trunc('#{interval}', performed_at)
        ) sources ON sources.performed_at = timestamp
        ORDER BY timestamp ASC
      SQL

      binds = [
        ActiveRecord::Relation::QueryAttribute.new('start_time', start_time, ActiveRecord::Type::DateTime.new),
        ActiveRecord::Relation::QueryAttribute.new('end_time', end_time, ActiveRecord::Type::DateTime.new),
      ]
      executions_data = GoodJob::Execution.connection.exec_query(GoodJob::Execution.pg_or_jdbc_query(count_query), "GoodJob Dashboard Chart", binds)

      labels = executions_data.map do |data|
        data['timestamp'].in_time_zone.strftime('%H:%M')
      end

      {
        labels: labels,
        datasets: [
          {
            label: 'min',
            data: executions_data.pluck('min'),
            stepped: true,
            borderColor: "hsl(0, 0%, 50%)",
            backgroundColor: "hsl(0, 0%, 50%)",
            fill: false,
          },
          {
            label: 'p95',
            data: executions_data.pluck('percentile_95'),
            stepped: true,
            borderColor: string_to_hsl('percentile_95'),
            backgroundColor: string_to_hsl('percentile_95'),
            fill: false,
          },
          {
            label: 'max',
            data: executions_data.pluck('max'),
            stepped: true,
            borderColor: "hsl(0, 0%, 30%)",
            backgroundColor: "hsl(0, 0%, 60%)",
            fill: "-2",
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
