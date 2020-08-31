# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::Configuration do
  describe '#execution_mode' do
    it 'defaults to :external' do
      configuration = described_class.new({})
      expect(configuration.execution_mode).to eq :external
    end

    context 'when an explicit default is passed' do
      it 'falls back to the default' do
        configuration = described_class.new({})
        expect(configuration.execution_mode(default: :truck)).to eq :truck
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
