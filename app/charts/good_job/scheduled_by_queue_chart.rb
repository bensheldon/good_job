# frozen_string_literal: true

module GoodJob
  class ScheduledByQueueChart
    def initialize(filter)
      @filter = filter
    end

    def data
      {
        type: 'line',
        data: {
          labels: labels,
          datasets: datasets
        },
        options: {
          animation: 'animate',
          responsive: true,
          maintainAspectRatio: false,
          scales: {
            y: {
              beginAtZero: true
            }
          }
        }
      }
    end

    protected

    def end_time
      @end_time ||= Time.current
    end

    def start_time
      @start_time ||= end_time - 1.day
    end

    def table_name
      table_name ||= GoodJob::Job.table_name
    end

    def count_query
      @count_query ||= Arel.sql(GoodJob::Execution.pg_or_jdbc_query(<<~SQL.squish))
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
              #{@filter.filtered_query.except(:select, :order).select('queue_name', "COALESCE(#{table_name}.scheduled_at, #{table_name}.created_at)::timestamp AS scheduled_at").to_sql}
            ) sources
            GROUP BY date_trunc('hour', scheduled_at), queue_name
        ) sources ON sources.scheduled_at = timestamp
        ORDER BY timestamp ASC
      SQL
    end

    def executions_data
      @executions_data ||= GoodJob::Execution.connection.exec_query(GoodJob::Execution.pg_or_jdbc_query(count_query), "GoodJob Dashboard Chart", binds)
    end

    def queues_data
      @queues_data ||= executions_data.to_a.group_by { |d| d['timestamp'] }.each_with_object({}) do |(timestamp, values), hash|
        queue_names.each do |queue_name|
          (hash[queue_name] ||= []) << values.find { |d| d['queue_name'] == queue_name }&.[]('count')
        end
      end
    end

    def queue_names
      @queue_names ||= executions_data.reject { |d| d['count'].nil? }.map { |d| d['queue_name'] || BaseFilter::EMPTY }.uniq
    end

    def binds
      @binds ||= [
        ActiveRecord::Relation::QueryAttribute.new('start_time', start_time, ActiveRecord::Type::DateTime.new),
        ActiveRecord::Relation::QueryAttribute.new('end_time', end_time, ActiveRecord::Type::DateTime.new),
      ]
    end

    def datasets
      queues_data.map do |queue, data|
        label = queue || '(none)'
        {
          label: label,
          data: data,
          backgroundColor: string_to_hsl(label),
          borderColor: string_to_hsl(label),
        }
      end
    end

    def labels
      @labels ||= executions_data.map { |row| row['timestamp'].in_time_zone.strftime('%H:%M') }
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
