# frozen_string_literal: true
module GoodJob
  class PerformancesController < GoodJob::ApplicationController
    def index
      @filter = GoodJob::PerformanceFilter.new(params)
    end
  end
end
