# frozen_string_literal: true

module GoodJob
  # Renders an execution's heavier details on demand so they aren't included in every job page.
  class ExecutionsController < GoodJob::ApplicationController
    def show
      @execution = Execution.find_by!(id: params[:id], active_job_id: params[:job_id])
      render layout: false
    end
  end
end
