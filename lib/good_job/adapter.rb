module GoodJob
  class Adapter
    def initialize(options = {})
      @options = options
      @scheduler = InlineScheduler.new if inline?
    end

    def inline?
      @options.fetch(:inline, false)
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
      @scheduler.enqueue(good_job) if inline?
    end

    def shutdown(wait: true)
      @scheduler&.shutdown(wait: wait)
    end
  end
end
