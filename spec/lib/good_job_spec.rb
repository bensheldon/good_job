# frozen_string_literal: true
require 'rails_helper'

describe GoodJob do
  let(:configuration) { GoodJob::Configuration.new({ queues: 'mice:1', poll_interval: -1 }) }

  describe '.shutdown' do
    it 'shuts down all capsules' do
      capsule = GoodJob::Capsule.new(configuration: configuration)
      capsule.start
      expect { described_class.shutdown }.to change(capsule, :shutdown?).from(false).to(true)
    end
  end

  describe '.shutdown?' do
    it 'returns whether any capsules are running' do
      expect do
        capsule = GoodJob::Capsule.new(configuration: configuration)
        capsule.start
      end.to change(described_class, :shutdown?).from(true).to(false)

      expect do
        described_class.shutdown
      end.to change(described_class, :shutdown?).from(false).to(true)
    end
  end

  describe '.restart' do
    it 'does nothing when there are no capsule instances' do
      expect(GoodJob::Capsule.instances).to be_empty
      expect { described_class.restart }.not_to change(described_class, :shutdown?).from(true)
    end

    it 'restarts down all capsule instances' do
      GoodJob::Capsule.new(configuration: configuration)
      expect { described_class.restart }.to change(described_class, :shutdown?).from(true).to(false)
    end
  end

  describe '.cleanup_preserved_jobs' do
    let!(:recent_job) { GoodJob::Execution.create!(active_job_id: SecureRandom.uuid, finished_at: 12.hours.ago) }
    let!(:old_unfinished_job) { GoodJob::Execution.create!(active_job_id: SecureRandom.uuid, scheduled_at: 15.days.ago, finished_at: nil) }
    let!(:old_finished_job) { GoodJob::Execution.create!(active_job_id: SecureRandom.uuid, finished_at: 15.days.ago) }
    let!(:old_finished_job_execution) { GoodJob::Execution.create!(active_job_id: old_finished_job.active_job_id, retried_good_job_id: old_finished_job.id, finished_at: 16.days.ago) }
    let!(:old_discarded_job) { GoodJob::Execution.create!(active_job_id: SecureRandom.uuid, finished_at: 15.days.ago, error: "Error") }
    let!(:old_batch) { GoodJob::BatchRecord.create!(finished_at: 15.days.ago) }

    it 'deletes finished jobs' do
      destroyed_records_count = described_class.cleanup_preserved_jobs

      expect(destroyed_records_count).to eq 4

      expect { recent_job.reload }.not_to raise_error
      expect { old_unfinished_job.reload }.not_to raise_error
      expect { old_finished_job.reload }.to raise_error ActiveRecord::RecordNotFound
      expect { old_discarded_job.reload }.to raise_error ActiveRecord::RecordNotFound
      expect { old_batch.reload }.to raise_error ActiveRecord::RecordNotFound
    end

    it 'takes arguments' do
      destroyed_records_count = described_class.cleanup_preserved_jobs(older_than: 10.seconds)

      expect(destroyed_records_count).to eq 5

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
      allow(described_class.configuration).to receive(:env).and_return ENV.to_hash.merge({ 'GOOD_JOB_CLEANUP_DISCARDED_JOBS' => 'false' })
      destroyed_records_count = described_class.cleanup_preserved_jobs

      expect(destroyed_records_count).to eq 3

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
