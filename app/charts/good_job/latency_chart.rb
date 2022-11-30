module GoodJob
  class LatencyChart < BaseChart
    VALID_INTERVALS = %w[second minute hour day].freeze

    attr_reader :window, :interval

    INTERVALS = {
      second: 2.minutes,
      minute: 2.hours,
      hour: 5.days,
      day: 120.days,
    }

    def initialize(filter, interval: :second, window: nil)
      interval = interval.to_sym
      raise ArgumentError, "interval must be one of #{INTERVALS.keys}" unless INTERVALS.keys.include?(interval)

      @filter = filter
      @interval = interval
      @window = INTERVALS[interval].ago..Time.current
    end

    def data
      @_data ||= begin
        subselect = @filter.filtered_query
                           .except(:select, :order)
                           .select(:queue_name, :created_at, :scheduled_at, :performed_at, :finished_at)

        count_query = Arel.sql(GoodJob::Execution.pg_or_jdbc_query(<<~SQL.squish))
          SELECT *
          FROM generate_series(
            date_trunc('#{interval}', $1::timestamp),
            date_trunc('#{interval}', $2::timestamp),
            '1 #{interval}'::interval
          ) timestamp
          LEFT JOIN (
            SELECT
                queue_name,
                date_trunc('#{interval}', COALESCE(performed_at, NOW())) as performed_at,
                EXTRACT('epoch' FROM AVG(COALESCE(performed_at, NOW()) - COALESCE(scheduled_at, created_at))) AS queue_latency_avg,
                EXTRACT('epoch' FROM MAX(COALESCE(performed_at, NOW()) - COALESCE(scheduled_at, created_at))) AS queue_latency_max,
                EXTRACT('epoch' FROM percentile_disc(0.95) WITHIN group (ORDER BY (COALESCE(performed_at, NOW()) - COALESCE(scheduled_at, created_at)))) AS queue_latency_p95
              FROM (
                #{(subselect.where(performed_at: @window).or(subselect.where(performed_at: nil).where("COALESCE(scheduled_at, created_at) <= ?", @window.last))).to_sql}
              ) queue_sources
              GROUP BY
                date_trunc('#{interval}', COALESCE(performed_at, NOW())),
                queue_name
          ) queue_latency ON queue_latency.performed_at = timestamp
          LEFT JOIN (
            SELECT
                queue_name,
                date_trunc('#{interval}', COALESCE(finished_at, NOW())) as finished_at,
                EXTRACT('epoch' FROM AVG(COALESCE(finished_at, NOW()) - performed_at)) AS perform_latency_avg,
                EXTRACT('epoch' FROM MAX(COALESCE(finished_at, NOW()) - performed_at)) AS perform_latency_max,
                EXTRACT('epoch' FROM percentile_disc(0.95) WITHIN group (ORDER BY (COALESCE(finished_at, NOW()) - performed_at))) AS perform_latency_p95
              FROM (
                #{(subselect.where(finished_at: @window).or(subselect.where(finished_at: nil).where("performed_at <= ?", @window.last))).to_sql}
              ) queue_sources
              GROUP BY
                date_trunc('#{interval}', COALESCE(finished_at, NOW())),
                queue_name
          ) perform_latency ON perform_latency.finished_at = timestamp
          LEFT JOIN (
            SELECT
                queue_name,
                date_trunc('#{interval}', COALESCE(finished_at, NOW())) as finished_at,
                EXTRACT('epoch' FROM AVG(COALESCE(finished_at, NOW()) - COALESCE(scheduled_at, created_at))) AS total_latency_avg,
                EXTRACT('epoch' FROM MAX(COALESCE(finished_at, NOW()) - COALESCE(scheduled_at, created_at))) AS total_latency_max,
                EXTRACT('epoch' FROM percentile_disc(0.95) WITHIN group (ORDER BY (COALESCE(finished_at, NOW()) - COALESCE(scheduled_at, created_at)))) AS total_latency_p95
              FROM (
                #{(subselect.where(finished_at: @window).or(subselect.where(finished_at: nil).where("performed_at <= ?", @window.last))).to_sql}
              ) queue_sources
              GROUP BY
                date_trunc('#{interval}', COALESCE(finished_at, NOW())),
                queue_name
          ) total_latency ON total_latency.finished_at = timestamp
          ORDER BY timestamp ASC
        SQL

        binds = [
          ActiveRecord::Relation::QueryAttribute.new('start_time', @window.first, ActiveRecord::Type::DateTime.new),
          ActiveRecord::Relation::QueryAttribute.new('end_time', @window.last, ActiveRecord::Type::DateTime.new),
        ]

        GoodJob::Execution.connection.exec_query(GoodJob::Execution.pg_or_jdbc_query(count_query), "GoodJob Dashboard Chart", binds)
      end
    end

    def queue_latency
      chart_for('queue_latency_avg')
    end

    def perform_latency
      chart_for('perform_latency_avg')
    end

    def total_latency
      chart_for('total_latency_avg')
    end

    def chart_for(field)
      queue_names = data.reject { |d| d[field].nil? }.map { |d| d['queue_name'] || BaseFilter::EMPTY }.uniq
      labels = []
      queues_data = data.to_a.group_by { |d| d['timestamp'] }.each_with_object({}) do |(timestamp, values), hash|
        labels << timestamp.in_time_zone.strftime('%H:%M:%S')
        queue_names.each do |queue_name|
          (hash[queue_name] ||= []) << values.find { |d| d['queue_name'] == queue_name }&.[](field)
        end
      end

      {
        labels: labels,
        datasets: queues_data.map do |queue, data|
          label = queue || '(none)'
          {
            label: label,
            data: data,
            backgroundColor: string_to_hsl(label),
            borderColor: string_to_hsl(label),
          }
        end
      }

    end
  end
end

