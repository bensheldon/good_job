# frozen_string_literal: true

module GoodJob
  # The measurements the Performance charts plot and the index tables aggregate.
  module LatencyMetric
    PARAMETER_KEY = :chart

    def self.options
      [
        GoodJob::LatencyMetric::Execution.new,
        GoodJob::LatencyMetric::Queue.new,
        GoodJob::LatencyMetric::Total.new,
      ]
    end

    def self.default = options.first

    def self.table_aggregates_sql
      <<~SQL.squish
        COUNT(DISTINCT active_job_id) AS jobs_count,
        COUNT(*) AS executions_count,
        AVG(#{GoodJob::LatencyMetric::Queue::EXPRESSION}) AS avg_queue,
        MIN(#{GoodJob::LatencyMetric::Queue::EXPRESSION}) AS min_queue,
        MAX(#{GoodJob::LatencyMetric::Queue::EXPRESSION}) AS max_queue,
        AVG(#{GoodJob::LatencyMetric::Execution::EXPRESSION}) AS avg_execution,
        MIN(#{GoodJob::LatencyMetric::Execution::EXPRESSION}) AS min_execution,
        MAX(#{GoodJob::LatencyMetric::Execution::EXPRESSION}) AS max_execution,
        AVG(#{GoodJob::LatencyMetric::Total::EXPRESSION}) AS avg_total,
        MIN(#{GoodJob::LatencyMetric::Total::EXPRESSION}) AS min_total,
        MAX(#{GoodJob::LatencyMetric::Total::EXPRESSION}) AS max_total
      SQL
    end

    # Compare as strings: the value is whatever the query string held, so array- and
    # hash-valued input has to fall through to the default rather than be coerced.
    def self.from_params(params)
      key = params[PARAMETER_KEY]

      options.find { |metric| metric.key.to_s == key } || default
    end
  end
end
