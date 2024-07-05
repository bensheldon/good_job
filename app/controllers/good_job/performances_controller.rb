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
                          AVG(duration) AS avg_duration,
                          MIN(duration) AS min_duration,
                          MAX(duration) AS max_duration
                        ")
                        .order("job_class")
    end
  end
end
