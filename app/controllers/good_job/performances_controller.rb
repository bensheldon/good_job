# frozen_string_literal: true
module GoodJob
  class PerformancesController < GoodJob::ApplicationController
    def show
      interval_param = params.fetch(:interval, :second).to_sym
      @interval = interval_param.in?(LatencyChart::INTERVALS.keys) ? interval_param : :second
      @filter = JobsFilter.new(params)
      @latency_chart = LatencyChart.new(@filter, interval: @interval)
    end
  end
end
