# frozen_string_literal: true

module GoodJob
  class PerformanceController < ApplicationController
    def index
      @performances = GoodJob::Execution
                      .where.not(job_class: nil)
                      .group(:job_class)
                      .select("
                            job_class,
                            COUNT(*) AS executions_count,
                            AVG(duration) AS avg_duration,
                            MIN(duration) AS min_duration,
                            MAX(duration) AS max_duration
                          ")
                      .order("job_class")
    end

    def show
      representative_job = GoodJob::Job.find_by!(job_class: params[:id])
      @job_class = representative_job.job_class
    end
  end
end
