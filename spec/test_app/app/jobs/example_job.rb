class ExampleJob < ApplicationJob
  RUN_JOBS = Concurrent::Array.new
  THREAD_JOBS = Concurrent::Hash.new(Concurrent::Array.new)
  ExpectedError = Class.new(StandardError)
  RetryableError = Class.new(StandardError)

  retry_on(RetryableError, wait: 0, attempts: 3) do |job, error|
    # puts "FAILED"
  end

  def perform(*args, result: nil, sleep_time: nil, raise_error: nil)
    RUN_JOBS << provider_job_id

    thread_name = Thread.current.name || Thread.current.object_id
    THREAD_JOBS[thread_name] << provider_job_id

    sleep(sleep_time) if sleep_time
    if raise_error == :retryable
      raise RetryableError, "Raised retryable error"
    elsif raise_error
      raise ExpectedError, "Raised expected error"
    end

    result
  end
end
