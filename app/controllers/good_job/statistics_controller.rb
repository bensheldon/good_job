# frozen_string_literal: true

module GoodJob
  class StatisticsController < ApplicationController

    def index
      @job_classes = GoodJob::Execution.pluck(:job_class).uniq.sort
    end

    def show
      @job_class  = params[:id]
      @chart_data = StatisticsJobClassChart.new(@job_class).data
      @count      = GoodJob::Execution.where(job_class: @job_class)
                                      .finished
                                      .count
      @runtimes   = GoodJob::Execution.where(job_class: @job_class)
                                      .finished
                                      .map { |execution| execution.runtime_latency }
                                      .compact
    end
  end
end
