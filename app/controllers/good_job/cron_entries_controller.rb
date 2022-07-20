# frozen_string_literal: true
module GoodJob
  class CronEntriesController < GoodJob::ApplicationController
    def index
      @cron_entries = CronEntry.all
    end

    def show
      @cron_entry = CronEntry.find(params[:cron_key])
      @jobs_filter = JobsFilter.new(params, @cron_entry.jobs)
    end

    def enqueue
      @cron_entry = CronEntry.find(params[:cron_key])
      @cron_entry.enqueue(Time.current)
      redirect_back(fallback_location: cron_entries_path, notice: "Cron entry has been enqueued.")
    end

    def enable
      @cron_entry = CronEntry.find(params[:cron_key])
      @cron_entry.enable
      redirect_back(fallback_location: cron_entries_path, notice: "Cron has been enabled.")
    end

    def disable
      @cron_entry = CronEntry.find(params[:cron_key])
      @cron_entry.disable
      redirect_back(fallback_location: cron_entries_path, notice: "Cron has been disabled.")
    end
  end
end
