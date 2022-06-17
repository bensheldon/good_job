# frozen_string_literal: true
require 'rails_helper'

describe GoodJob do
  let(:configuration) { GoodJob::Configuration.new({ queues: 'mice:1', poll_interval: -1 }) }
  let!(:scheduler) { GoodJob::Scheduler.from_configuration(configuration) }
  let!(:notifier) { GoodJob::Notifier.new([scheduler, :create_thread]) }

  describe '.shutdown' do
    it 'shuts down all scheduler and notifier instances' do
      described_class.shutdown

      expect(scheduler.shutdown?).to be true
      expect(notifier.shutdown?).to be true
    end
  end

  describe '.shutdown?' do
    it 'shuts down all scheduler and notifier instances' do
      expect do
        described_class.shutdown
      end.to change(described_class, :shutdown?).from(false).to(true)
    end
  end

  describe '.restart' do
    it 'restarts down all scheduler and notifier instances' do
      described_class.shutdown

      expect do
        described_class.restart
      end.to change(described_class, :shutdown?).from(true).to(false)
    end
  end

  describe '.cleanup_preserved_jobs' do
    let!(:recent_job) { GoodJob::Execution.create!(active_job_id: SecureRandom.uuid, finished_at: 12.hours.ago) }
    let!(:old_unfinished_job) { GoodJob::Execution.create!(active_job_id: SecureRandom.uuid, scheduled_at: 2.days.ago, finished_at: nil) }
    let!(:old_finished_job) { GoodJob::Execution.create!(active_job_id: SecureRandom.uuid, finished_at: 36.hours.ago) }
    let!(:old_discarded_job) { GoodJob::Execution.create!(active_job_id: SecureRandom.uuid, finished_at: 36.hours.ago, error: "Error") }

    it 'destroys finished jobs' do
      destroyed_jobs_count = described_class.cleanup_preserved_jobs

      expect(destroyed_jobs_count).to eq 2

      expect { recent_job.reload }.not_to raise_error
      expect { old_unfinished_job.reload }.not_to raise_error
      expect { old_finished_job.reload }.to raise_error ActiveRecord::RecordNotFound
      expect { old_discarded_job.reload }.to raise_error ActiveRecord::RecordNotFound
    end

    it 'takes arguments' do
      destroyed_jobs_count = described_class.cleanup_preserved_jobs(older_than: 10.seconds)

      expect(destroyed_jobs_count).to eq 3

      expect { recent_job.reload }.to raise_error ActiveRecord::RecordNotFound
      expect { old_unfinished_job.reload }.not_to raise_error
      expect { old_finished_job.reload }.to raise_error ActiveRecord::RecordNotFound
      expect { old_discarded_job.reload }.to raise_error ActiveRecord::RecordNotFound
    end

    it 'is instrumented' do
      payloads = []
      callback = proc { |*args| payloads << args }

      ActiveSupport::Notifications.subscribed(callback, "cleanup_preserved_jobs.good_job") do
        described_class.cleanup_preserved_jobs
      end

      expect(payloads.size).to eq 1
    end

    it "respects the cleanup_discarded_jobs? configuration" do
      stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_CLEANUP_DISCARDED_JOBS' => 'false' })

      destroyed_jobs_count = described_class.cleanup_preserved_jobs

      expect(destroyed_jobs_count).to eq 1

      expect { recent_job.reload }.not_to raise_error
      expect { old_unfinished_job.reload }.not_to raise_error
      expect { old_finished_job.reload }.to raise_error ActiveRecord::RecordNotFound
      expect { old_discarded_job.reload }.not_to raise_error
    end
  end

  describe '.perform_inline' do
    before do
      stub_const 'PERFORMED', []
      stub_const 'JobError', Class.new(StandardError)
      stub_const 'TestJob', (Class.new(ActiveJob::Base) do
        self.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)

        def perform(succeed: true)
          PERFORMED << Time.current
          raise JobError unless succeed
        end
      end)
    end

    it 'executes performable jobs' do
      TestJob.perform_later
      TestJob.perform_later
      TestJob.set(wait: 1.minute).perform_later

      described_class.perform_inline
      expect(PERFORMED.size).to eq 2
    end

    it 'raises unhandled exceptions' do
      TestJob.perform_later(succeed: false)

      expect do
        described_class.perform_inline
      end.to raise_error JobError
    end

    it 'executes future scheduled jobs' do
      TestJob.set(wait: 5.minutes).perform_later

      expect(PERFORMED.size).to eq 0
      travel_to(6.minutes.from_now) do
        described_class.perform_inline
      end
      expect(PERFORMED.size).to eq 1
    end
  end
end
