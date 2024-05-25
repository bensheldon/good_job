# frozen_string_literal: true

module GoodJob
  class StatisticsController < ApplicationController
    def index
      @job_classes = GoodJob::Execution.pluck(:job_class).uniq.sort
    end
  end
end
