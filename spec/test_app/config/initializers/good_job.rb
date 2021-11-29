Rails.application.configure do
  config.good_job.cron = {
    example: {
      cron: '*/5 * * * * *', # every 5 seconds
      class: 'ExampleJob',
      description: "Enqueue ExampleJob every 5 seconds",
    },
  }
end

case Rails.env
when 'development'
  ActiveJob::Base.queue_adapter = :good_job

  GoodJob.retry_on_unhandled_error = false
  GoodJob.preserve_job_records = true
  GoodJob.on_thread_error = -> (error) { Rails.logger.warn(error) }

  Rails.application.configure do
    config.good_job.enable_cron = ActiveModel::Type::Boolean.new.cast(ENV.fetch('GOOD_JOB_ENABLE_CRON', true))
    config.good_job.cron = {
      frequent_example: {
        description: "Enqueue an ExampleJob",
        cron: "*/5 * * * * *",
        class: "ExampleJob",
        args: (lambda do
          [ExampleJob::TYPES.sample.to_s]
        end),
        set: (lambda do
          queue = [:default, :elephants, :mice].sample
          delay = [0, (0..60).to_a.sample].sample
          priority = [-10, 0, 10].sample

          { wait: delay, queue: queue, priority: priority }
        end),
      },
    }
  end
when 'test'
  # test
when 'demo'
  ActiveJob::Base.queue_adapter = :good_job

  GoodJob.preserve_job_records = true
  GoodJob.retry_on_unhandled_error = false

  Rails.application.configure do
    config.good_job.execution_mode = :async
    config.good_job.poll_interval = 30

    config.good_job.enable_cron = true
    config.good_job.cron = {
      frequent_example: {
        description: "Enqueue an ExampleJob with a random sample of configuration",
        cron: "* * * * * *",
        class: "ExampleJob",
        args: (lambda do
          [ExampleJob::TYPES.sample.to_s]
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
      },
    }
  end
when 'production'
  ActiveJob::Base.queue_adapter = :good_job
end
