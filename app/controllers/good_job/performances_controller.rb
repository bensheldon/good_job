# frozen_string_literal: true

module GoodJob
  class PerformancesController < ApplicationController
    def index
      @performances = GoodJob::DiscreteExecution
                        .where.not(job_class: nil)
                        .group(:job_class)
                        .select("
                          job_class,
                          COUNT(*) AS executions_count,
                          AVG(EXTRACT(EPOCH FROM (finished_at - created_at))) AS avg_duration,
                          MIN(EXTRACT(EPOCH FROM (finished_at - created_at))) AS min_duration,
                          MAX(EXTRACT(EPOCH FROM (finished_at - created_at))) AS max_duration
                        ")
                        .order("job_class")
    end
  end
end
