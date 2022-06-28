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

    def toggle
      cs = GoodJob::CronEntryStatus.where(key: params[:cron_key]).first
      cs.active = !cs.active
      cs.save!
      @cron_entry = GoodJob::CronEntry.find(params[:cron_key])
    end
  end
end
