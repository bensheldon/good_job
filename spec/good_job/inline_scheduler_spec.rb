require 'rails_helper'

RSpec.describe GoodJob::InlineScheduler do
  let(:adapter) { GoodJob::Adapter.new(inline: true) }

  around do |example|
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = adapter
    example.run
    ActiveJob::Base.queue_adapter = original_adapter
  end

  before do
    stub_const "RUN_JOBS", Concurrent::Array.new

    stub_const 'ExampleJob', (Class.new(ApplicationJob) do
      self.queue_name = 'test'
      self.priority = 50

      def perform(*args, **kwargs)
        RUN_JOBS << { args: args, kwargs: kwargs }
      end
    end)
  end

  describe '#enqeue' do
    it 'passes parameters to the job' do
      ExampleJob.perform_later('first', 'second', keyword_arg: 'keyword_arg')

      expect(RUN_JOBS.first).to eq({
                                     args: ['first', 'second'],
                                     kwargs: { keyword_arg: 'keyword_arg' }
                                   })
    end
  end
end
