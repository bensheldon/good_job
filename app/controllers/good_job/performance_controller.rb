# frozen_string_literal: true

module GoodJob
  class PerformanceController < ApplicationController
    def index
      @performances = GoodJob::Execution.group(:job_class).select("
        job_class,
        COUNT(*) AS executions_count,
        AVG(duration) AS avg_duration,
        MIN(duration) AS min_duration,
        MAX(duration) AS max_duration
      ").order(:job_class)

      @queue_performances = GoodJob::Execution.group(:queue_name).select("
        queue_name,
        COUNT(*) AS executions_count,
        AVG(duration) AS avg_duration,
        MIN(duration) AS min_duration,
        MAX(duration) AS max_duration
      ").order(:queue_name)

      @paused_job_classes = Array(GoodJob::Setting.where(key: :paused_job_classes).pick(:value))
      @paused_queues = Array(GoodJob::Setting.where(key: :paused_queues).pick(:value))
    end

    def show
      representative_job = GoodJob::Job.find_by!(job_class: params[:id])
      @job_class = representative_job.job_class
    end

    def pause
      if params[:queue_name].present?
        GoodJob::Setting.pause(queue: params[:queue_name])
      elsif params[:job_class].present?
        GoodJob::Setting.pause(job_class: params[:job_class])
      end

      redirect_back(fallback_location: performance_index_path, notice: "Paused successfully")
    end

    def unpause
      if params[:queue_name].present?
        GoodJob::Setting.unpause(queue: params[:queue_name])
      elsif params[:job_class].present?
        GoodJob::Setting.unpause(job_class: params[:job_class])
      end

      redirect_back(fallback_location: performance_index_path, notice: "Unpaused successfully")
    end
  end
end
