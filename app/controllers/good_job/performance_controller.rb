# frozen_string_literal: true

module GoodJob
  class PerformanceController < ApplicationController
    before_action :set_performance_range

    def index
      executions = @performance_range.apply(GoodJob::Execution)

      @performances = executions.group(:job_class).select("
        job_class,
        COUNT(*) AS executions_count,
        AVG(duration) AS avg_duration,
        MIN(duration) AS min_duration,
        MAX(duration) AS max_duration
      ").order(:job_class)

      @queue_performances = executions.group(:queue_name).select("
        queue_name,
        COUNT(*) AS executions_count,
        AVG(duration) AS avg_duration,
        MIN(duration) AS min_duration,
        MAX(duration) AS max_duration
      ").order(:queue_name)

      @chart_data = GoodJob::PerformanceIndexChart.new(@performance_range).data
    end

    def show
      representative_job = GoodJob::Job.find_by!(job_class: request.path_parameters.fetch(:id))
      @job_class = representative_job.job_class
      @chart_data = GoodJob::PerformanceShowChart.new(@job_class, @performance_range).data
    end

    private

    def set_performance_range
      locale = request.query_parameters["locale"]
      @performance_range_context = locale.is_a?(String) ? { "locale" => locale } : {}
      @performance_range = GoodJob::PerformanceRange.new(params, query_string: request.query_string)
      return if @performance_range.canonical_parameters?(request.query_parameters)

      canonical_query = @performance_range.to_params.symbolize_keys
      canonical_query[:locale] = @performance_range_context["locale"]
      canonical_path = if action_name == "show"
                         performance_path(request.path_parameters.fetch(:id), canonical_query)
                       else
                         performance_index_path(canonical_query)
                       end
      redirect_to canonical_path
    end
  end
end
