# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::Configuration do
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
    it 'defaults to 86400' do
      configuration = described_class.new({})
      expect(configuration.cleanup_preserved_jobs_before_seconds_ago).to eq 86400
    end

    context 'when environment variable is set' do
      before do
        stub_const 'ENV', ENV.to_hash.merge({ 'GOOD_JOB_CLEANUP_PRESERVED_JOBS_BEFORE_SECONDS_AGO' => 36000 })
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
end
