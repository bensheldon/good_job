class CleanupJob < ApplicationJob
  self.queue_name = :cleanup

  def perform(limit = 2_000)
    earliest_job_to_preserve = GoodJob::Job.finished.order(created_at: :desc).limit(limit).last
    return if earliest_job_to_preserve.blank?

    GoodJob::Job.where("created_at < ?", earliest_job_to_preserve.created_at).delete_all
  end
end
