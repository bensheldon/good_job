RSpec.configure do |config|
  # Disabled because this causes the same database connection to be reused across threads
  # which causes Advisory Locks to not be effective because they are locked per-connection/per-thread.
  config.use_transactional_fixtures = false

  config.after do
    GoodJob.shutdown
    GoodJob::Notifier.instances.clear
    GoodJob::Scheduler.instances.clear
    GoodJob::Timer.instances.clear
  end
end
