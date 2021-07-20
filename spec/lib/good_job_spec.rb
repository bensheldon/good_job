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

  describe '.reperform_jobs_on_standard_error' do
    around do |example|
      original_retry_on_unhandled_error = described_class.retry_on_unhandled_error
      example.run
      described_class.retry_on_unhandled_error = original_retry_on_unhandled_error
    end

    it 'is deprecated and replaced with .retry_on_unhandled_error' do
      allow(ActiveSupport::Deprecation).to receive(:warn)
      described_class.retry_on_unhandled_error = true

      expect do
        described_class.reperform_jobs_on_standard_error = false
      end.to(
        change(described_class, :retry_on_unhandled_error).from(true).to(false).and(
          change(described_class, :reperform_jobs_on_standard_error).from(true).to(false)
        )
      )

      expect(ActiveSupport::Deprecation).to have_received(:warn).exactly(3).times
    end
  end
end
