class CleanupJob < ApplicationJob
  self.queue_name = :cleanup

  def perform(*args)
    GoodJob.cleanup_preserved_jobs
  end
end
