# frozen_string_literal: true
module GoodJob
  class JobsController < GoodJob::ApplicationController
    rescue_from GoodJob::ActiveJobJob::AdapterNotGoodJobError,
                GoodJob::ActiveJobJob::ActionForStateMismatchError,
                with: :redirect_on_error

    def index
      @filter = JobsFilter.new(params)
    end

    def show
      @executions = GoodJob::Execution.active_job_id(params[:id])
                                      .order(Arel.sql("COALESCE(scheduled_at, created_at) DESC"))
      redirect_to root_path, alert: "Executions for Active Job #{params[:id]} not found" if @executions.empty?
    end

    def discard
      @job = ActiveJobJob.find(params[:id])
      @job.discard_job("Discarded through dashboard")
      redirect_back(fallback_location: jobs_path, notice: "Job has been discarded")
    end

    def reschedule
      @job = ActiveJobJob.find(params[:id])
      @job.reschedule_job
      redirect_back(fallback_location: jobs_path, notice: "Job has been rescheduled")
    end

    def retry
      @job = ActiveJobJob.find(params[:id])
      @job.retry_job
      redirect_back(fallback_location: jobs_path, notice: "Job has been retried")
    end

    private

    def redirect_on_error(exception)
      alert = case exception
              when GoodJob::ActiveJobJob::AdapterNotGoodJobError
                "ActiveJob Queue Adapter must be GoodJob."
              when GoodJob::ActiveJobJob::ActionForStateMismatchError
                "Job is not in an appropriate state for this action."
              else
                exception.to_s
              end
      redirect_back(fallback_location: jobs_path, alert: alert)
    end
  end
end
