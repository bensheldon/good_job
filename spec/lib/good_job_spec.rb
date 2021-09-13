# frozen_string_literal: true
require 'rails_helper'

describe GoodJob do
  let(:configuration) { GoodJob::Configuration.new({ queues: 'mice:1', poll_interval: -1 }) }
  let!(:scheduler) { GoodJob::Scheduler.from_configuration(configuration) }
  let!(:notifier) { GoodJob::Notifier.new([scheduler, :create_thread]) }

  describe '.shutdown' do
    it 'shuts down all scheduler and notifier instances' do
      described_class.shutdown

      expect(scheduler.shutdown?).to eq true
      expect(notifier.shutdown?).to eq true
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
    let!(:recent_job) { GoodJob::Execution.create!(finished_at: 12.hours.ago) }
    let!(:old_unfinished_job) { GoodJob::Execution.create!(scheduled_at: 2.days.ago, finished_at: nil) }
    let!(:old_finished_job) { GoodJob::Execution.create!(finished_at: 36.hours.ago) }

    it 'deletes finished jobs' do
      deleted_jobs_count = described_class.cleanup_preserved_jobs

      expect(deleted_jobs_count).to eq 1

      expect { recent_job.reload }.not_to raise_error
      expect { old_unfinished_job.reload }.not_to raise_error
      expect { old_finished_job.reload }.to raise_error ActiveRecord::RecordNotFound
    end

    it 'takes arguments' do
      deleted_jobs_count = described_class.cleanup_preserved_jobs(older_than: 10.seconds)

      expect(deleted_jobs_count).to eq 2

      expect { recent_job.reload }.to raise_error ActiveRecord::RecordNotFound
      expect { old_unfinished_job.reload }.not_to raise_error
      expect { old_finished_job.reload }.to raise_error ActiveRecord::RecordNotFound
    end

    it 'is instrumented' do
      allow(ActiveSupport::Notifications).to receive(:instrument).and_call_original

      described_class.cleanup_preserved_jobs

      expect(ActiveSupport::Notifications).to have_received(:instrument).at_least(:once)
    end
  end
end
