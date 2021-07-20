# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::CurrentExecution do
  describe '.error_on_discard' do
    it 'maintains value across threads' do
      described_class.error_on_discard = 'apple'

      Thread.new do
        described_class.error_on_discard = 'bear'
      end.join

      expect(described_class.error_on_discard).to eq 'apple'
    end

    it 'maintains value across Rails execution wrapper' do
      Rails.application.executor.wrap do
        described_class.error_on_discard = 'apple'
      end

      expect(described_class.error_on_discard).to eq 'apple'
    end

    it 'is resettable' do
      described_class.error_on_discard = 'apple'
      described_class.reset
      expect(described_class.error_on_discard).to eq nil
    end
  end

  describe '.error_on_retry' do
    it 'maintains value across threads' do
      described_class.error_on_retry = 'apple'

      Thread.new do
        described_class.error_on_retry = 'bear'
      end.join

      expect(described_class.error_on_retry).to eq 'apple'
    end

    it 'maintains value across Rails execution wrapper' do
      Rails.application.executor.wrap do
        described_class.error_on_retry = 'apple'
      end

      expect(described_class.error_on_retry).to eq 'apple'
    end

    it 'is resettable' do
      described_class.error_on_retry = 'apple'
      described_class.reset
      expect(described_class.error_on_retry).to eq nil
    end
  end

  describe '.active_job_id' do
    it 'is assignable, thread-safe, and resettable' do
      described_class.active_job_id = 'duck'

      Thread.new do
        described_class.active_job_id = 'bear'
      end.join

      expect(described_class.active_job_id).to eq 'duck'

      described_class.reset
      expect(described_class.active_job_id).to eq nil
    end
  end
end
