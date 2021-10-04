# frozen_string_literal: true
module GoodJob
  class CronSchedulesController < GoodJob::BaseController
    def index
      configuration = GoodJob::Configuration.new({})
      @cron_entries = configuration.cron_entries
    end
  end
end
