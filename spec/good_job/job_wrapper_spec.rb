require 'rails_helper'

RSpec.describe GoodJob::JobWrapper do
  around do |example|
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new
    example.run
    ActiveJob::Base.queue_adapter = original_adapter
  end

  before do
    stub_const 'ExampleJob', (Class.new(ApplicationJob) do
      def perform(*_args, **_kwargs)
        sleep 1
        true
      end
    end)
  end

  it "is a pending example"
end
