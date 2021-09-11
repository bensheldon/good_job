# frozen_string_literal: true

module GoodJob
  class CronSchedulesController < GoodJob::BaseController
    def index
      configuration = GoodJob::Configuration.new({})
      @cron_schedules = configuration.cron
    end
  end
end
