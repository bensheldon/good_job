# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Capsule' do
  it 'hands off and executes in a different capsule as if it was a separate process' do
    total_jobs = 250

    stub_const "LATCH", Concurrent::CountDownLatch.new(total_jobs)
    stub_const "TestJob", (Class.new(ActiveJob::Base) do
      def perform
        LATCH.count_down
      end
    end)

    enqueue_capsule = GoodJob::Capsule.new(configuration: GoodJob::Configuration.new({}))
    perform_capsule = GoodJob::Capsule.new(configuration: GoodJob::Configuration.new({ max_threads: 10 }))
    perform_capsule.start

    adapter = GoodJob::Adapter.new(execution_mode: :external, _capsule: enqueue_capsule)
    TestJob.queue_adapter = adapter

    total_jobs.times { TestJob.perform_later }

    LATCH.wait(10)
    wait_until { expect(GoodJob::Job.finished.count).to eq(total_jobs) }
    expect(GoodJob::DiscreteExecution.count).to eq(total_jobs)

    perform_capsule.shutdown
  end
end
