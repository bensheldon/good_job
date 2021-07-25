require_relative 'production'

GoodJob.preserve_job_records = true
GoodJob.retry_on_unhandled_error = false

Rails.application.configure do
  config.active_job.queue_adapter = :good_job
  config.good_job.execution_mode = :async_server
  config.good_job.poll_interval = 30
end
