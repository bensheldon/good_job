module GoodJob
  class MetricsController < ApplicationController
    def primary_nav
      jobs_count = number_to_human(GoodJob::Job.count)
      batches_count = number_to_human(GoodJob::BatchRecord.migrated? ? GoodJob::BatchRecord.all.size : 0)
      cron_entries_count = GoodJob::CronEntry.all.size
      render json: { jobs_count:, batches_count:, cron_entries_count:, }
    end

    private

    def number_to_human(count)
      helpers.number_to_human(count, **helpers.translate_hash("good_job.number.human.decimal_units"))
    end
  end
end
