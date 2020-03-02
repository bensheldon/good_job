module GoodJob
  class JobWrapper
    def initialize(good_job)
      @good_job = good_job
    end

    def perform
      serialized_params = @good_job.serialized_params.merge(
        "provider_job_id" => @good_job.id
      )
      ActiveJob::Base.execute(serialized_params)

      @good_job.destroy!
    end
  end
end
