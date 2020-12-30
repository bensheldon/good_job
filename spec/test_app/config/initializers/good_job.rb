if ENV['GOOD_JOB_EXECUTION_MODE'].present?
  ActiveJob::Base.queue_adapter = :good_job
end
