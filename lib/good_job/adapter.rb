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
        scheduled_at: timestamp ? Time.zone.at(timestamp) : nil,
        create_with_advisory_lock: inline?
      )

      if inline?
        begin
          good_job.perform
        ensure
          good_job.advisory_unlock
        end
      end

      good_job
    end

    def shutdown(wait: true) # rubocop:disable Lint/UnusedMethodArgument
      nil
    end

    def inline?
      @inline
    end
  end
end
