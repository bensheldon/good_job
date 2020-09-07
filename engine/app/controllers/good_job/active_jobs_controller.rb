module GoodJob
  class ActiveJobsController < GoodJob::BaseController
    def show
      @jobs = GoodJob::Job.where("serialized_params ->> 'job_id' = ?", params[:id])
                          .order('COALESCE(scheduled_at, created_at) DESC')
    end
  end
end
