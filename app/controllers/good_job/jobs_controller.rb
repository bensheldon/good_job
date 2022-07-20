# frozen_string_literal: true
module GoodJob
  class JobsController < GoodJob::ApplicationController
    DISCARD_MESSAGE = "Discarded through dashboard"

    ACTIONS = {
      discard: "discarded",
      reschedule: "rescheduled",
      retry: "retried",
      destroy: "destroyed",
    }.freeze

    rescue_from GoodJob::Job::AdapterNotGoodJobError,
                GoodJob::Job::ActionForStateMismatchError,
                with: :redirect_on_error

    def index
      @filter = JobsFilter.new(params)
    end

    def mass_update
      mass_action = params.fetch(:mass_action, "").to_sym
      raise ActionController::BadRequest, "#{mass_action} is not a valid mass action" unless mass_action.in?(ACTIONS.keys)

      jobs = if params[:all_job_ids]
               JobsFilter.new(params).filtered_query
             else
               job_ids = params.fetch(:job_ids, [])
               Job.where(active_job_id: job_ids)
             end

      processed_jobs = jobs.map do |job|
        case mass_action
        when :discard
          job.discard_job(DISCARD_MESSAGE)
        when :reschedule
          job.reschedule_job
        when :retry
          job.retry_job
        when :destroy
          job.destroy_job
        end

        job
      rescue GoodJob::Job::ActionForStateMismatchError
        nil
      end.compact

      notice = if processed_jobs.any?
                 "Successfully #{ACTIONS[mass_action]} #{processed_jobs.count} #{'job'.pluralize(processed_jobs.count)}"
               else
                 "No jobs were #{ACTIONS[mass_action]}"
               end

      redirect_back(fallback_location: jobs_path, notice: notice)
    end

    def show
      @job = Job.includes_advisory_locks.find(params[:id])
    end

    def discard
      @job = Job.find(params[:id])
      @job.discard_job(DISCARD_MESSAGE)
      redirect_back(fallback_location: jobs_path, notice: "Job has been discarded")
    end

    def reschedule
      @job = Job.find(params[:id])
      @job.reschedule_job
      redirect_back(fallback_location: jobs_path, notice: "Job has been rescheduled")
    end

    def retry
      @job = Job.find(params[:id])
      @job.retry_job
      redirect_back(fallback_location: jobs_path, notice: "Job has been retried")
    end

    def destroy
      @job = Job.find(params[:id])
      @job.destroy_job
      redirect_back(fallback_location: jobs_path, notice: "Job has been destroyed")
    end

    private

    def redirect_on_error(exception)
      alert = case exception
              when GoodJob::Job::AdapterNotGoodJobError
                "ActiveJob Queue Adapter must be GoodJob."
              when GoodJob::Job::ActionForStateMismatchError
                "Job is not in an appropriate state for this action."
              else
                exception.to_s
              end
      redirect_back(fallback_location: jobs_path, alert: alert)
    end
  end
end
