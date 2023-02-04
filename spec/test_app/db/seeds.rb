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

GoodJob::Execution.insert_all(jobs_data)
puts "Inserted #{jobs_data.size} job records for a total of #{GoodJob::Execution.count} job records."

puts ActiveJob::Base.queue_adapter

100.times do
  GoodJob::Batch.enqueue(on_finish: ExampleJob::BatchCallbackJob, seeded: Time.current) do
    (1..5).to_a.sample.times do
      job_type = [
        ExampleJob::SUCCESS_TYPE,
        ExampleJob::SUCCESS_TYPE,
        ExampleJob::SUCCESS_TYPE,
        ExampleJob::ERROR_ONCE_TYPE,
        ExampleJob::DEAD_TYPE
      ].sample
      ExampleJob.perform_later(job_type)
    end
  end
end
puts "Inserted 100 batches"
