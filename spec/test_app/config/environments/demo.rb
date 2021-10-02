require_relative 'production'

GoodJob.preserve_job_records = true
GoodJob.retry_on_unhandled_error = false

Rails.application.configure do
  config.active_job.queue_adapter = :good_job
  config.good_job.execution_mode = :async
  config.good_job.poll_interval = 30

  config.good_job.enable_cron = true
  config.good_job.cron = {
    frequent_example: {
      description: "Enqueue an ExampleJob with a random sample of configuration",
      cron: "* * * * * *",
      class: "ExampleJob",
      args: (lambda do
        type = ExampleJob::TYPES.sample
        [type.to_s]
      end),
      set: (lambda do
        queue = [:default, :elephants, :mice].sample
        delay = [0, (0..60).to_a.sample].sample
        priority = [-10, 0, 10].sample

        { wait: delay, queue: queue, priority: priority }
      end),
    },
    other_example: {
      description: "Enqueue an OtherJob occasionally",
      cron: "*/15 * * * * *",
      class: "OtherJob",
      set: { queue: :default },
    },
    cleanup: {
      description: "Delete old jobs.",
      cron: "*/15 * * * *",
      class: "CleanupJob",
      args: { limit: 1_000 },
    },
  }
end
