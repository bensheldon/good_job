module GoodJob
  class JobsController < GoodJob::BaseController
    def destroy
      deleted_count = GoodJob::Job.where(id: params[:id]).delete_all
      message = deleted_count.positive? ? { notice: "Job deleted" } : { alert: "Job not deleted" }
      redirect_to root_path, **message
    end
  end
end
