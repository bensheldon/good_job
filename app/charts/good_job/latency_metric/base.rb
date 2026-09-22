# frozen_string_literal: true

module GoodJob
  module LatencyMetric
    # A measurement the Performance charts can plot. Subclasses supply a SQL
    # expression over +good_job_executions+, the aggregate that summarizes it per
    # time bucket, and their titles.
    class Base
      def expression = self.class::EXPRESSION

      def to_arel = Arel.sql(expression)

      # nil plots an empty bucket as a gap; a summed metric overrides this with a true zero.
      def empty_value = nil

      def to_params = { PARAMETER_KEY => key.to_s }

      def span_gaps? = empty_value.nil?
    end
  end
end
