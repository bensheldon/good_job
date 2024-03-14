# frozen_string_literal: true

module GoodJob
  class MetricsController < ApplicationController
    def primary_nav
      jobs_count = GoodJob::Job.count
      batches_count = GoodJob::BatchRecord.migrated? ? GoodJob::BatchRecord.all.size : 0
      cron_entries_count = GoodJob::CronEntry.all.size
      processes_count = GoodJob::Process.active.count

      render json: {
        jobs_count: number_to_human(jobs_count),
        batches_count: number_to_human(batches_count),
        cron_entries_count: number_to_human(cron_entries_count),
        processes_count: number_to_human(processes_count),
      }
    end

    private

    def number_to_human(count)
      helpers.number_to_human(count, **helpers.translate_hash("good_job.number.human.decimal_units"))
    end
  end
end
