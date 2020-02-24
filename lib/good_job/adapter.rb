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
      good_job = GoodJob::Job.create(
        queue_name: job.queue_name,
        priority: job.priority,
        serialized_params: job.serialize
      )

      @scheduler.enqueue(good_job) if inline?
    end

    def enqueue_at(job, timestamp)
      good_job = GoodJob::Job.create(
        queue_name: job.queue_name,
        priority: job.priority,
        serialized_params: job.serialize,
        scheduled_at: Time.at(timestamp)
      )

      @scheduler.enqueue(good_job) if inline?
    end

    def shutdown(wait: true)
      @scheduler.shutdown(wait: wait) if @scheduler
    end
  end
end
