# frozen_string_literal: true
module GoodJob
  class CronEntriesController < GoodJob::ApplicationController
    before_action :check_settings_migration!, only: [:enable, :disable]

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
      redirect_back(fallback_location: cron_entries_path, notice: "Cron entry has been enabled.")
    end

    def disable
      @cron_entry = CronEntry.find(params[:cron_key])
      @cron_entry.disable
      redirect_back(fallback_location: cron_entries_path, notice: "Cron entry has been disabled.")
    end

    private

    def check_settings_migration!
      redirect_back(fallback_location: cron_entries_path, alert: "Requires pending GoodJob database migration.") unless GoodJob::Setting.migrated?
    end
  end
end
