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
    perform_capsule.shutdown
    enqueue_capsule.shutdown

    expect(GoodJob::DiscreteExecution.count).to eq(total_jobs)
  end

  it 'computes ilde base on configuation' do
    stub_const "TestJob", (Class.new(ActiveJob::Base) do
      def perform
        # noop
      end
    end)

    never_idle_capsule = GoodJob::Capsule.new(configuration: GoodJob::Configuration.new({}))
    idle_capsule = GoodJob::Capsule.new(configuration: GoodJob::Configuration.new({shutdown_on_idle: 10}))
    never_idle_capsule.start
    idle_capsule.start

    expect(never_idle_capsule.idle?).to be(false)

    adapter = GoodJob::Adapter.new(execution_mode: :async, _capsule: idle_capsule)
    TestJob.queue_adapter = adapter
    TestJob.perform_later

    GoodJob.perform_inline

    expect(idle_capsule.idle?).to be(false)

    travel_to Time.now.utc + 30.seconds do
      expect(idle_capsule.idle?).to be(true)
    end
  end
end
