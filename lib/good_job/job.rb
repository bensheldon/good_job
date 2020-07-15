module GoodJob
  class Job < ActiveRecord::Base
    include Lockable

    self.table_name = 'good_jobs'

    scope :only_scheduled, -> { where("scheduled_at < ?", Time.current).or(where(scheduled_at: nil)) }
    scope :priority_ordered, -> { order(priority: :desc) }
    scope :to_performer, -> { Performer.new(self) }

    class Performer
      def initialize(query)
        @query = query
      end

      def next
        good_job = nil

        @query.limit(1).with_advisory_lock do |good_jobs|
          good_job = good_jobs.first
          break unless good_job

          good_job.perform
        end

        good_job
      end
    end

    def self.enqueue(active_job, scheduled_at: nil, create_with_advisory_lock: false)
      good_job = nil
      ActiveSupport::Notifications.instrument("enqueue_job.good_job", { active_job: active_job, scheduled_at: scheduled_at, create_with_advisory_lock: create_with_advisory_lock }) do |instrument_payload|
        good_job = GoodJob::Job.new(
          queue_name: active_job.queue_name,
          priority: active_job.priority,
          serialized_params: active_job.serialize,
          scheduled_at: scheduled_at,
          create_with_advisory_lock: create_with_advisory_lock
        )

        instrument_payload[:good_job] = good_job

        good_job.save!
        active_job.provider_job_id = good_job.id
      end

      good_job
    end

    def perform
      ActiveSupport::Notifications.instrument("before_perform_job.good_job", { good_job: self })
      ActiveSupport::Notifications.instrument("perform_job.good_job", { good_job: self }) do
        params = serialized_params.merge(
          "provider_job_id" => id
        )
        ActiveJob::Base.execute(params)

        destroy!
      end
    end
  end
end
