module GoodJob
  class Adapter
    def initialize(inline: false)
      @inline = inline
    end

    def enqueue(active_job)
      enqueue_at(active_job, nil)
    end

    def enqueue_at(active_job, timestamp)
      good_job = GoodJob::Job.enqueue(
        active_job,
        scheduled_at: timestamp ? Time.at(timestamp) : nil,
        create_with_advisory_lock: inline?
      )

      if inline?
        good_job.perform
        good_job.advisory_unlock
      end

      good_job
    end

    def shutdown(wait: true) # rubocop:disable Lint/UnusedMethodArgument
      nil
    end

    private

    def inline?
      @inline
    end
  end
end
