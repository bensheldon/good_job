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
      use_original_locale { @cron_entry.enqueue(Time.current) }
      redirect_back(fallback_location: cron_entries_path, notice: t(".notice"))
    end

    def enable
      @cron_entry = CronEntry.find(params[:cron_key])
      @cron_entry.enable
      redirect_back(fallback_location: cron_entries_path, notice: t(".notice"))
    end

    def disable
      @cron_entry = CronEntry.find(params[:cron_key])
      @cron_entry.disable
      redirect_back(fallback_location: cron_entries_path, notice: t(".notice"))
    end

    private

    def check_settings_migration!
      redirect_back(fallback_location: cron_entries_path, alert: t("good_job.cron_entries.pending_migrations")) unless GoodJob::Setting.migrated?
    end
  end
end
