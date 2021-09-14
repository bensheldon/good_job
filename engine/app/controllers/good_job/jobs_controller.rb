# frozen_string_literal: true
module GoodJob
  class JobsController < GoodJob::BaseController
    def index
      @filter = JobsFilter.new(params)
    end

    def show
      @executions = GoodJob::Execution.active_job_id(params[:id])
                                      .order(Arel.sql("COALESCE(scheduled_at, created_at) DESC"))
      redirect_to root_path, alert: "Executions for Active Job #{params[:id]} not found" if @executions.empty?
    end
  end
end
