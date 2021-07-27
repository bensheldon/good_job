class CleanupJob < ApplicationJob
  def perform(limit: 5_000)
    earliest = GoodJob::Job.finished.order(created_at: :desc).limit(limit).last.created_at
    GoodJob::Job.where("created_at < ?", earliest).delete_all
  end
end
