# frozen_string_literal: true

module GoodJob
  class PerformancesController < ApplicationController

    def index
      @job_classes = GoodJob::Execution.pluck(:job_class).uniq.sort
    end

    def show
      @job_class  = params[:id]
      @chart_data = StatisticsJobClassChart.new(@job_class).data
      @count      = executions.count
      @runtimes   = executions.map { |execution| execution.runtime_latency }.compact
      @longest_executions = executions.reject { |execution| execution.runtime_latency.nil? }
                                      .sort_by(&:runtime_latency)
                                      .reverse
                                      .first(10)
    end

    protected

    def executions
      GoodJob::Execution.where(job_class: @job_class).finished
    end
  end
end
