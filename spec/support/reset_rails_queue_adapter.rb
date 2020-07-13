RSpec.configure do |config|
  config.around do |example|
    original_adapter = ActiveJob::Base.queue_adapter
    example.run
    ActiveJob::Base.queue_adapter = original_adapter
  end
end
