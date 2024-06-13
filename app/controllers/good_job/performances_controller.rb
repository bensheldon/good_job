# frozen_string_literal: true

module GoodJob
  class PerformancesController < ApplicationController

    def index
      @job_classes = GoodJob::Execution.pluck(:job_class).uniq.sort
    end

    protected

    def executions
      GoodJob::Execution.where(job_class: @job_class).finished
    end
  end
end
