# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::ActiveJobExtensions::Concurrency do
  before do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)

    stub_const 'TestJob', (Class.new(ActiveJob::Base) do
      include GoodJob::ActiveJobExtensions::Concurrency

      good_job_control_concurrency_with(
        enqueue_limit: 2,
        perform_limit: 0,
        key: -> { arguments.first[:name] }
      )

      def perform(name:)
        name && sleep(1)
      end
    end)
  end

  describe '.good_job_control_concurrency_with' do
    describe 'enqueue_limit', skip_rails_5: true do
      it "does not enqueue if enqueue concurrency limit is exceeded for a particular key" do
        expect(TestJob.perform_later(name: "Alice")).to be_present
        expect(TestJob.perform_later(name: "Alice")).to be_present

        # Third usage of key does not enqueue
        expect(TestJob.perform_later(name: "Alice")).to eq false

        # Usage of different key does enqueue
        expect(TestJob.perform_later(name: "Bob")).to be_present

        expect(GoodJob::Job.where(concurrency_key: "Alice").count).to eq 2
        expect(GoodJob::Job.where(concurrency_key: "Bob").count).to eq 1
      end
    end

    describe 'perform_limit' do
      before do
        allow(GoodJob).to receive(:preserve_job_records).and_return(true)
      end

      it "will error and retry jobs if concurrency is exceeded" do
        TestJob.perform_later(name: "Alice")

        performer = GoodJob::JobPerformer.new('*')
        scheduler = GoodJob::Scheduler.new(performer, max_threads: 5)
        5.times { scheduler.create_thread }

        sleep_until(max: 10, increments_of: 0.5) do
          GoodJob::Job.where(concurrency_key: "Alice").finished.count >= 1
        end
        scheduler.shutdown

        expect(GoodJob::Job.count).to be >= 1
        expect(GoodJob::Job.where("error LIKE '%GoodJob::ActiveJobExtensions::Concurrency::ConcurrencyExceededError%'")).to be_present
      end
    end
  end
end
