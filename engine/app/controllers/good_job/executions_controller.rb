# frozen_string_literal: true
module GoodJob
  class ExecutionsController < GoodJob::ApplicationController
    def destroy
      destroyed_count = GoodJob::Execution.where(id: params[:id]).destroy_all
      message = destroyed_count.positive? ? { notice: "Job execution destroyed" } : { alert: "Job execution not destroyed" }
      redirect_back fallback_location: jobs_path, **message
    end
  end
end
