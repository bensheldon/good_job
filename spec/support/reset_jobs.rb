RSpec.configure do |config|
  config.after do
    ExampleJob::RUN_JOBS.clear
    ExampleJob::THREAD_JOBS.clear
  end
end
