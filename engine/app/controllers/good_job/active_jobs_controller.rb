module GoodJob
  class ActiveJobsController < GoodJob::BaseController
    def show
      @jobs = GoodJob::Job.where("serialized_params ->> 'job_id' = ?", params[:id])
                          .order(Arel.sql("COALESCE(scheduled_at, created_at) DESC"))
    end

    def destroy
      deleted_count = GoodJob::Job.where(id: params[:id]).delete_all
      message = deleted_count.positive? ? { notice: "Job deleted" } : { alert: "Job not deleted" }
      redirect_to root_path, **message
    end
  end
end
