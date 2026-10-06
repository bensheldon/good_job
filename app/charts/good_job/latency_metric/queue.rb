# frozen_string_literal: true

module GoodJob
  module LatencyMetric
    # How long jobs waited between becoming eligible and actually starting, the same
    # quantity as GoodJob::Execution#queue_latency. Averaged across a bucket because a
    # summed wait would grow with volume alone.
    class Queue < Base
      EXPRESSION = "(created_at - scheduled_at)"

      def key = :queue

      def aggregate = "AVG"

      def presence_sql = "scheduled_at IS NOT NULL"

      def chart_title = I18n.t("good_job.performance.index.chart_title_queue")

      def histogram_title = I18n.t("good_job.performance.show.queue_chart_title")
    end
  end
end
