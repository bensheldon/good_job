# frozen_string_literal: true
module GoodJob
  class CronEntriesController < GoodJob::BaseController
    def index
      @cron_entries = CronEntry.all
    end

    def show
      @cron_entry = CronEntry.find(params[:id])
      @jobs_filter = JobsFilter.new(params, @cron_entry.jobs)
    end

    def enqueue
      @cron_entry = CronEntry.find(params[:id])
      @cron_entry.enqueue(Time.current)
      redirect_back(fallback_location: cron_entries_path, notice: "Cron entry has been enqueued.")
    end
  end
end
