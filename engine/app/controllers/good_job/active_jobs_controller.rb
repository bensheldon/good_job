module GoodJob
  class ActiveJobsController < GoodJob::BaseController
    def show
      @jobs = GoodJob::Job.where("serialized_params ->> 'job_id' = ?", params[:id])
                          .order(Arel.sql("COALESCE(scheduled_at, created_at) DESC"))
    end

    def destroy
      GoodJob::Job.where("serialized_params ->> 'job_id' = ?", params[:id]).delete_all
      redirect_to root_path, notice: "Job deleted"
    end
  end
end
