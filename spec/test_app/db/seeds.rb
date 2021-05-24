start_date = 7.days.ago
time_increments = (1.minute..90.minutes).to_a
job_classes = ['ExampleJob', 'OtherJob']
queue_names = ["default", "mice", "elephants"]

ActiveRecord::Base.transaction do
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

    GoodJob::Job.create(
      created_at: enqueued_at,
      updated_at: enqueued_at,
      queue_name: queue_name,
      priority: 0,
      serialized_params: serialized_params,
      scheduled_at: nil,
      performed_at: nil,
      finished_at: nil,
      error: nil
    )

    start_date += time_increments.sample
    break if start_date > Time.current
  end
end
