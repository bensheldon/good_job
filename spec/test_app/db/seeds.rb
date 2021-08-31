start_date = 7.days.ago
time_increments = (1.minute..10.minutes).to_a
job_classes = ['ExampleJob', 'OtherJob']
queue_names = ["default", "mice", "elephants"]

jobs_data = []
loop do
  active_job_id = SecureRandom.uuid
  job_class = job_classes.sample
  queue_name = queue_names.sample
  enqueued_at = start_date

  serialized_params = {
    job_id: active_job_id,
    locale: "en",
    priority: nil,
    timezone: "Pacific Time (US & Canada)",
    arguments: [true],
    job_class: job_class,
    executions: 0,
    queue_name: queue_name,
    enqueued_at: enqueued_at,
    provider_job_id: nil,
    exception_executions: {}
  }

  jobs_data << {
    active_job_id: active_job_id,
    created_at: enqueued_at,
    updated_at: enqueued_at,
    queue_name: queue_name,
    priority: 0,
    serialized_params: serialized_params,
    scheduled_at: nil,
    performed_at: nil,
    finished_at: nil,
    error: nil
  }

  start_date += time_increments.sample
  break if start_date > Time.current
end

GoodJob::Job.insert_all(jobs_data)
puts "Inserted #{jobs_data.size} job records for a total of #{GoodJob::Job.count} job records."
