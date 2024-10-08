# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::Setting do
  describe 'implicit sort order' do
    it 'is by created_at' do
      first_job = described_class.create(id: '67160140-1bec-4c3b-bc34-1a8b36f87b21')
      described_class.create(id: '3732d706-fd5a-4c39-b1a5-a9bc6d265811')
      last_job = described_class.create(id: '4fbae77c-6f22-488f-ad42-5bd20f39c28c')

      result = described_class.all

      expect(result.first).to eq first_job
      expect(result.last).to eq last_job
    end
  end

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

      it 'does not insert duplicate keys' do
        expect(described_class.where(key: described_class::CRON_KEYS_DISABLED).count).to eq 0

        described_class.cron_key_disable(:test)
        described_class.cron_key_disable(:test)
        expect(described_class.where(key: described_class::CRON_KEYS_DISABLED).count).to eq 1
        expect(described_class.find_by(key: described_class::CRON_KEYS_DISABLED).value).to contain_exactly 'test'

        described_class.cron_key_enable(:test)
        expect(described_class.find_by(key: described_class::CRON_KEYS_DISABLED).value).to eq []
      end
    end
  end

  describe 'cron_key_enabled setting' do
    describe '.cron_key_enable' do
      it 'inserts values into a json array' do
        expect(described_class.where(key: described_class::CRON_KEYS_ENABLED).count).to eq 0

        described_class.cron_key_enable(:test)
        expect(described_class.where(key: described_class::CRON_KEYS_ENABLED).count).to eq 1
        expect(described_class.find_by(key: described_class::CRON_KEYS_ENABLED).value).to contain_exactly 'test'

        described_class.cron_key_enable(:test_2)
        expect(described_class.where(key: described_class::CRON_KEYS_ENABLED).count).to eq 1
        expect(described_class.find_by(key: described_class::CRON_KEYS_ENABLED).value).to contain_exactly "test", "test_2"

        described_class.cron_key_disable(:test)
        described_class.cron_key_disable(:test_2)
        expect(described_class.find_by(key: described_class::CRON_KEYS_ENABLED).value).to eq []
      end

      it 'does not insert duplicate keys' do
        expect(described_class.where(key: described_class::CRON_KEYS_ENABLED).count).to eq 0

        described_class.cron_key_enable(:test)
        described_class.cron_key_enable(:test)
        expect(described_class.where(key: described_class::CRON_KEYS_ENABLED).count).to eq 1
        expect(described_class.find_by(key: described_class::CRON_KEYS_ENABLED).value).to contain_exactly 'test'

        described_class.cron_key_disable(:test)
        expect(described_class.find_by(key: described_class::CRON_KEYS_ENABLED).value).to eq []
      end
    end
  end
end
