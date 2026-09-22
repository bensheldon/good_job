# frozen_string_literal: true

module GoodJob
  module LatencyMetric
    # How long jobs took end to end: the wait before starting plus the run itself.
    # Averaged across a bucket for the same reason as Queue.
    class Total < Base
      # NULL while an execution is still running, so the aggregates skip it rather than count zero.
      EXPRESSION = "(#{GoodJob::LatencyMetric::Queue::EXPRESSION} + #{GoodJob::LatencyMetric::Execution::EXPRESSION})".freeze

      def key = :total

      def aggregate = "AVG"

      def presence_sql = "scheduled_at IS NOT NULL AND duration IS NOT NULL"

      def chart_title = I18n.t("good_job.performance.index.chart_title_total")

      def histogram_title = I18n.t("good_job.performance.show.total_chart_title")
    end
  end
end
