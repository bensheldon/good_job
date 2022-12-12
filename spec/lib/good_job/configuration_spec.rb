# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::Configuration do
  describe '.total_estimated_threads' do
    before do
      allow(ActiveRecord::Base.connection_pool).to receive(:size).and_return(2)
    end

    it 'counts up the total estimated threads' do
      expect(described_class.total_estimated_threads).to eq 1
    end

    it 'outputs a warning message' do
      allow(ActiveRecord::Base.connection_pool).to receive(:size).and_return(0)
      allow(GoodJob.logger).to receive(:warn)

      described_class.total_estimated_threads(warn: true)

      expect(GoodJob.logger).to have_received(:warn).with(/GoodJob is using \d+ threads/)
    end
  end

  describe '#execution_mode' do
    context 'when in development' do
      before do
        allow(Rails).to receive(:env) { "development".inquiry }
      end

      it 'defaults to :inline' do
        configuration = described_class.new({})
        expect(configuration.execution_mode).to eq :async
      end
    end

    context 'when in test' do
      before do
        allow(Rails).to receive(:env) { "test".inquiry }
      end

      it 'defaults to :inline' do
        configuration = described_class.new({})
        expect(configuration.execution_mode).to eq :inline
      end
    end

    context 'when in production' do
      before do
        allow(Rails).to receive(:env) { "production".inquiry }
      end

      it 'defaults to :external' do
        configuration = described_class.new({})
        expect(configuration.execution_mode).to eq :external
      end
    end
  end

  describe '#cleanup_discarded_jobs?' do
    it 'defaults to true' do
      configuration = described_class.new({})
      expect(configuration.cleanup_discarded_jobs?).to be true
    end

    context 'when rails config is set' do
      before do
        allow(Rails.application.config).to receive(:good_job).and_return({ cleanup_discarded_jobs: false })
      end

      it 'uses rails config value' do
        configuration = described_class.new({})
        expect(configuration.cleanup_discarded_jobs?).to be false
      end
    end

    context 'when environment variable is set' do
      before do
        stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_CLEANUP_DISCARDED_JOBS' => 'false' })
      end

      it 'uses environment variable' do
        configuration = described_class.new({})
        expect(configuration.cleanup_discarded_jobs?).to be false
      end
    end
  end

  describe '#cleanup_preserved_jobs_before_seconds_ago' do
    it 'defaults to 14 days' do
      configuration = described_class.new({})
      expect(configuration.cleanup_preserved_jobs_before_seconds_ago).to eq 14.days.to_i
    end

    context 'when environment variable is set' do
      before do
        stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_CLEANUP_PRESERVED_JOBS_BEFORE_SECONDS_AGO' => '36000' })
      end

      context 'when option is given' do
        it 'uses option value' do
          configuration = described_class.new({ before_seconds_ago: 10000 })
          expect(configuration.cleanup_preserved_jobs_before_seconds_ago).to eq 10000
        end
      end

      context 'when option is not given' do
        it 'uses environment variable' do
          configuration = described_class.new({})
          expect(configuration.cleanup_preserved_jobs_before_seconds_ago).to eq 36000
        end
      end
    end
  end

  describe '#cleanup_interval_jobs' do
    it 'defaults to 1000' do
      configuration = described_class.new({})
      expect(configuration.cleanup_interval_jobs).to eq 1000
    end

    context 'when rails config is set' do
      it 'uses rails config value' do
        allow(Rails.application.config).to receive(:good_job).and_return({ cleanup_interval_jobs: 10000 })

        configuration = described_class.new({})
        expect(configuration.cleanup_interval_jobs).to eq 10000
      end

      it 'accepts nil' do
        allow(Rails.application.config).to receive(:good_job).and_return({ cleanup_interval_jobs: nil })

        configuration = described_class.new({})
        expect(configuration.cleanup_interval_jobs).to be_nil
      end
    end

    context 'when environment variable is set' do
      it 'uses environment variable' do
        stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_CLEANUP_INTERVAL_JOBS' => '50000' })

        configuration = described_class.new({})
        expect(configuration.cleanup_interval_jobs).to eq 50000
      end

      it 'accepts an empty value' do
        stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_CLEANUP_INTERVAL_JOBS' => '' })

        configuration = described_class.new({})
        expect(configuration.cleanup_interval_jobs).to be_nil
      end
    end
  end

  describe '#cleanup_interval_seconds' do
    it 'defaults to 10 minutes' do
      configuration = described_class.new({})
      expect(configuration.cleanup_interval_seconds).to eq 10.minutes.to_i
    end

    context 'when rails config is set' do
      it 'uses rails config value' do
        allow(Rails.application.config).to receive(:good_job).and_return({ cleanup_interval_seconds: 1.hour })

        configuration = described_class.new({})
        expect(configuration.cleanup_interval_seconds).to eq 3600
      end

      it 'accepts nil' do
        allow(Rails.application.config).to receive(:good_job).and_return({ cleanup_interval_seconds: nil })

        configuration = described_class.new({})
        expect(configuration.cleanup_interval_seconds).to be_nil
      end
    end

    context 'when environment variable is set' do
      it 'uses environment variable' do
        stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_CLEANUP_INTERVAL_SECONDS' => '7200' })

        configuration = described_class.new({})
        expect(configuration.cleanup_interval_seconds).to eq 7200
      end

      it 'accepts an empty value' do
        stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_CLEANUP_INTERVAL_SECONDS' => '' })

        configuration = described_class.new({})
        expect(configuration.cleanup_interval_seconds).to be_nil
      end
    end
  end
end
