require_relative 'production'

GoodJob.preserve_job_records = true
GoodJob.retry_on_unhandled_error = false

Rails.application.configure do
  config.active_job.queue_adapter = :good_job
  config.good_job.execution_mode = :async_server
  config.good_job.poll_interval = 30

  config.good_job.enable_cron = true
  config.good_job.cron = {
    frequent_example: {
      description: "Enqueue an ExampleJob with a random sample of configuration",
      cron: "*/5 * * * * *", # every 5 seconds
      class: "ExampleJob",
      args: [],
      set: (lambda do
        queue = [:default, :elephants, :mice].sample
        delay = (0..60).to_a.sample
        priority = [-10, 0, 10].sample

        { wait: delay, queue: queue, priority: priority }
      end),
    },
    other_example: {
      description: "Enqueue an OtherJob occasionally",
      cron: "* * * * *", # every minute
      class: "OtherJob",
      set: { queue: :default },
    },
    cleanup: {
      description: "Delete old jobs every hour",
      cron: "0 * * * *", # every hour
      class: "CleanupJob",
      set: { queue: :default },
    }
  }
end
