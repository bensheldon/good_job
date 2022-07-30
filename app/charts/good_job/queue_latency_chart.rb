module GoodJob
  class QueueLatencyChart
    VALID_INTERVALS = %w[second minute hour day].freeze

    attr_reader :window, :interval

    def initialize(filter, window: 2.minutes.ago..Time.current, interval: 'second')
      raise ArgumentError, "interval must be one of #{VALID_INTERVALS}" unless VALID_INTERVALS.include?(interval)

      @filter = filter
      @window = window
      @interval = interval
    end

    def data
      subselect = @filter.filtered_query
                          .except(:select, :order)
                          .select(:created_at, :scheduled_at, :performed_at, :finished_at)

      count_query = Arel.sql(GoodJob::Execution.pg_or_jdbc_query(<<~SQL.squish))
        SELECT *
        FROM generate_series(
          date_trunc('#{interval}', $1::timestamp),
          date_trunc('#{interval}', $2::timestamp),
          '1 #{interval}'::interval
        ) timestamp
        LEFT JOIN (
          SELECT
              date_trunc('#{interval}', performed_at) as performed_at,
              EXTRACT('epoch' FROM MIN(performed_at - COALESCE(scheduled_at, created_at))) AS queue_latency_min,
              EXTRACT('epoch' FROM AVG(performed_at - COALESCE(scheduled_at, created_at))) AS queue_latency_avg,
              EXTRACT('epoch' FROM MAX(performed_at - COALESCE(scheduled_at, created_at))) AS queue_latency_max
            FROM (
              #{subselect.where(performed_at: @window).to_sql}
            ) queue_sources
            GROUP BY date_trunc('#{interval}', performed_at)
        ) queue_sources ON queue_sources.performed_at = timestamp
        LEFT JOIN (
          SELECT
              date_trunc('#{interval}', finished_at) as finished_at,
              EXTRACT('epoch' FROM MIN(finished_at - performed_at)) AS execution_latency_min,
              EXTRACT('epoch' FROM AVG(finished_at - performed_at)) AS execution_latency_avg,
              EXTRACT('epoch' FROM MAX(finished_at - performed_at)) AS execution_latency_max,
              EXTRACT('epoch' FROM MIN(finished_at - COALESCE(scheduled_at, created_at))) AS total_latency_min,
              EXTRACT('epoch' FROM AVG(finished_at - COALESCE(scheduled_at, created_at))) AS total_latency_avg,
              EXTRACT('epoch' FROM MAX(finished_at - COALESCE(scheduled_at, created_at))) AS total_latency_max
            FROM (
              #{subselect.where(finished_at: @window).to_sql}
            ) execution_sources
            GROUP BY date_trunc('#{interval}', finished_at)
        ) execution_sources ON execution_sources.finished_at = timestamp
        ORDER BY timestamp ASC
      SQL

      binds = [
        ActiveRecord::Relation::QueryAttribute.new('start_time', @window.first, ActiveRecord::Type::DateTime.new),
        ActiveRecord::Relation::QueryAttribute.new('end_time', @window.last, ActiveRecord::Type::DateTime.new),
      ]
      executions_data = GoodJob::Execution.connection.exec_query(GoodJob::Execution.pg_or_jdbc_query(count_query), "GoodJob Dashboard Chart", binds)

      executions_data.to_a
    end
  end
end

