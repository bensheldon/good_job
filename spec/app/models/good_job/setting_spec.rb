# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::Setting do
  describe 'cron_key_disabled setting' do
    describe '.cron_key_enabled?' do
      it 'returns true when the key is not disabled' do
        expect(described_class.cron_key_enabled?(:test)).to be true

        described_class.cron_key_disable(:test)
        expect(described_class.cron_key_enabled?(:test)).to be false

        described_class.cron_key_enable(:test)
        expect(described_class.cron_key_enabled?(:test)).to be true
      end
    end

    describe '.cron_key_disable' do
      it 'inserts values into a json array' do
        expect(described_class.where(key: described_class::CRON_KEYS_DISABLED).count).to eq 0

        described_class.cron_key_disable(:test)
        expect(described_class.where(key: described_class::CRON_KEYS_DISABLED).count).to eq 1
        expect(described_class.find_by(key: described_class::CRON_KEYS_DISABLED).value).to contain_exactly 'test'

        described_class.cron_key_disable(:test_2)
        expect(described_class.where(key: described_class::CRON_KEYS_DISABLED).count).to eq 1
        expect(described_class.find_by(key: described_class::CRON_KEYS_DISABLED).value).to contain_exactly "test", "test_2"

        described_class.cron_key_enable(:test)
        described_class.cron_key_enable(:test_2)
        expect(described_class.find_by(key: described_class::CRON_KEYS_DISABLED).value).to eq []
      end
    end

    describe '.cron_key_enable' do
      it 'removes values from a json array' do
        described_class.cron_key_disable(:test)
        described_class.cron_key_enable(:test)

        expect(described_class.find_by(key: described_class::CRON_KEYS_DISABLED).value).to eq []
      end
    end
  end
end
