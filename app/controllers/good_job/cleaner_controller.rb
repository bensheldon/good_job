# frozen_string_literal: true

module GoodJob
  class CleanerController < ApplicationController
    def index
      @filter = JobsFilter.new(params)

      @discarded_jobs_grouped_by_exception =
        GoodJob::Job.discarded
                    .select(<<-SQL.squish)
                      SPLIT_PART(error, ': ', 1) AS exception_class,
                      count(id) AS failed,
                      COUNT(id) FILTER (WHERE "finished_at" > NOW() - INTERVAL '1 HOUR') AS last_1_hour,
                      COUNT(id) FILTER (WHERE "finished_at" > NOW() - INTERVAL '3 HOURS') AS last_3_hours,
                      COUNT(id) FILTER (WHERE "finished_at" > NOW() - INTERVAL '24 HOURS') AS last_24_hours,
                      COUNT(id) FILTER (WHERE "finished_at" > NOW() - INTERVAL '3 DAYS') AS last_3_days,
                      COUNT(id) FILTER (WHERE "finished_at" > NOW() - INTERVAL '7 DAYS') AS last_7_days
                    SQL
                    .order(:exception_class)
                    .group(:exception_class)

      @discarded_jobs_grouped_by_class =
        GoodJob::Job.discarded
                    .select(<<-SQL.squish)
                      job_class,
                      count(id) AS failed,
                      COUNT(*) FILTER (WHERE "finished_at" > NOW() - INTERVAL '1 HOUR') AS last_1_hour,
                      COUNT(*) FILTER (WHERE "finished_at" > NOW() - INTERVAL '3 HOURS') AS last_3_hours,
                      COUNT(*) FILTER (WHERE "finished_at" > NOW() - INTERVAL '24 HOURS') AS last_24_hours,
                      COUNT(*) FILTER (WHERE "finished_at" > NOW() - INTERVAL '3 DAYS') AS last_3_days,
                      COUNT(*) FILTER (WHERE "finished_at" > NOW() - INTERVAL '7 DAYS') AS last_7_days
                    SQL
                    .order(:job_class)
                    .group(:job_class)
    end
  end
end
