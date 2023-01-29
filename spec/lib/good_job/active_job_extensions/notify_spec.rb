# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::ActiveJobExtensions::Notify do
  before do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)

    allow(GoodJob::Notifier).to receive(:notify)

    stub_const 'TestJob', (Class.new(ActiveJob::Base) do
      include GoodJob::ActiveJobExtensions::Notify

      def perform
      end
    end)
  end

  it 'notifies by default' do
    TestJob.perform_later
    expect(GoodJob::Notifier).to have_received(:notify)
  end

  it 'does not notify when good_job_notify is false' do
    TestJob.set(good_job_notify: false).perform_later
    expect(GoodJob::Notifier).not_to have_received(:notify)
  end

  it 'only serializes the key when it is explicitly set' do
    job = TestJob.perform_later
    expect(job.serialize).not_to have_key('good_job_notify')

    job = TestJob.set(good_job_notify: true).perform_later
    expect(job.serialize).to have_key('good_job_notify')

    job = TestJob.set(good_job_notify: false).perform_later
    expect(job.serialize).to have_key('good_job_notify')
  end

  context 'when a job is retried' do
    before do
      stub_const 'ExpectedError', Class.new(StandardError)
      stub_const 'TestJob', (Class.new(ActiveJob::Base) do
        include GoodJob::ActiveJobExtensions::Notify
        retry_on ExpectedError, wait: 0, attempts: 2

        def perform
          raise ExpectedError if executions == 1
        end
      end)
    end

    it 'does not notify when the job is retried' do
      TestJob.set(good_job_notify: false).perform_later

      performer = GoodJob::JobPerformer.new('*')
      scheduler = GoodJob::Scheduler.new(performer, max_threads: 5)
      scheduler.create_thread

      sleep_until(max: 5, increments_of: 0.5) { GoodJob::Execution.count >= 2 }
      scheduler.shutdown

      expect(GoodJob::Notifier).not_to have_received(:notify)
    end
  end
end
