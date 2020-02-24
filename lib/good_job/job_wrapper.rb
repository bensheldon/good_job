module GoodJob
  class JobWrapper
    def initialize(good_job)
      @good_job = good_job
    end

    def perform
      # Rails.logger.info "Perform job_id #{@good_job.id}: on thread #{Thread.current.name}"
      @good_job.with_advisory_lock do
        @good_job.reload

        serialized_params = @good_job.serialized_params.merge(
          "provider_job_id" => @good_job.id
        )
        ActiveJob::Base.execute(serialized_params)

        @good_job.destroy!
      end
    end
  end
end
