# frozen_string_literal: true

module GoodJob
  module LatencyMetric
    # How long jobs took to run. Summed across a bucket because total execution time
    # is a measure of load.
    class Execution < Base
      EXPRESSION = "duration"

      def key = :execution

      def aggregate = "SUM"

      def presence_sql = "duration IS NOT NULL"

      def empty_value = 0

      # The default metric stays out of navigation URLs.
      def to_params = {}

      def chart_title = I18n.t("good_job.performance.index.chart_title")

      def histogram_title = I18n.t("good_job.performance.show.execution_chart_title")
    end
  end
end
