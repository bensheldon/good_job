datetime = 7.days.ago
time_series =  (1.minute..90.minutes).to_a

ActiveRecord::Base.transaction do
  loop do
    active_job_id = SecureRandom.uuid
    job_class = ['ExampleJob', 'OtherJob'].sample
    queue_name = ["default", "mice", "elephants"].sample
    enqueued_at = datetime

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

    datetime += time_series.sample
    break if datetime > Time.current
  end
end
