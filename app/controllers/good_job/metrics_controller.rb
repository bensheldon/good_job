# frozen_string_literal: true

module GoodJob
  class MetricsController < ApplicationController
    def primary_nav
      jobs_count = GoodJob::Job.count
      batches_count = GoodJob::BatchRecord.all.size
      cron_entries_count = GoodJob::CronEntry.all.size
      processes_count = GoodJob::Process.active.count

      render json: {
        jobs_count: helpers.number_to_human(jobs_count),
        batches_count: helpers.number_to_human(batches_count),
        cron_entries_count: helpers.number_to_human(cron_entries_count),
        processes_count: helpers.number_to_human(processes_count),
      }
    end

    def job_status
      @filter = JobsFilter.new(params)

      render json: @filter.states.transform_values { |count| helpers.number_with_delimiter(count) }
    end
  end
end
