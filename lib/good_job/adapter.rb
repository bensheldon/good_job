module GoodJob
  class Adapter
    def initialize(options = {})
      @options = options
      @scheduler = InlineScheduler.new if inline?
    end

    def enqueue(job)
      enqueue_at(job, nil)
    end

    def enqueue_at(job, timestamp)
      params = {
        queue_name: job.queue_name,
        priority: job.priority,
        serialized_params: job.serialize,
      }
      params[:scheduled_at] = Time.at(timestamp) if timestamp

      good_job = GoodJob::Job.create(params)
      job.provider_job_id = good_job.id

      GoodJob.tag_logger do
        ActiveSupport::Notifications.instrument("create.good_job", { good_job: good_job, job: job })
        @scheduler.enqueue(good_job) if inline?
      end

      good_job
    end

    def shutdown(wait: true)
      @scheduler&.shutdown(wait: wait)
    end

    private

    def inline?
      @options.fetch(:inline, false)
    end
  end
end
