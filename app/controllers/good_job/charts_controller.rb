# frozen_string_literal: true
module GoodJob
  class ChartsController < GoodJob::ApplicationController
    def index
      @filter = GoodJob::ChartsFilter.new(params)
    end
  end
end
