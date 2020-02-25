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
      def perform(*args, **kwargs)
        sleep 1
        true
      end
    end)
  end

  it 'locks the job and prevents from being run at same time twice' do
    ExampleJob.perform_later

    good_job = GoodJob::Job.last
    expect(good_job).to be_present

    thread1 = Concurrent::Promises.future(good_job) { |j| GoodJob::JobWrapper.new(j).perform }
    thread2 = Concurrent::Promises.future(good_job) { |j| GoodJob::JobWrapper.new(j).perform }

    expect do
      Concurrent::Promises.zip(thread1, thread2).value!
    end.to raise_error GoodJob::Lockable::RecordAlreadyAdvisoryLockedError
  end
end
