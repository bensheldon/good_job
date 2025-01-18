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

  describe 'pause settings' do
    describe '.pause' do
      it 'raises ArgumentError if neither queue nor job_class is provided' do
        expect { described_class.pause }.to raise_error(ArgumentError, "Must provide either queue or job_class, but not both")
      end

      it 'raises ArgumentError if both queue and job_class are provided' do
        expect { described_class.pause(queue: "default", job_class: "MyJob") }.to raise_error(ArgumentError, "Must provide either queue or job_class, but not both")
      end

      context 'with queue' do
        it 'inserts values into a json array' do
          expect(described_class.where(key: described_class::PAUSES).count).to eq 0

          described_class.pause(queue: "default")
          expect(described_class.where(key: described_class::PAUSES).count).to eq 1
          expect(described_class.find_by(key: described_class::PAUSES).value["queues"]).to contain_exactly "default"

          described_class.pause(queue: "mailers")
          expect(described_class.where(key: described_class::PAUSES).count).to eq 1
          expect(described_class.find_by(key: described_class::PAUSES).value["queues"]).to contain_exactly "default", "mailers"

          described_class.unpause(queue: "default")
          described_class.unpause(queue: "mailers")
          expect(described_class.find_by(key: described_class::PAUSES).value["queues"]).to eq []
        end

        it 'does not insert duplicate queue names' do
          described_class.pause(queue: "default")
          described_class.pause(queue: "default")
          expect(described_class.where(key: described_class::PAUSES).count).to eq 1
          expect(described_class.find_by(key: described_class::PAUSES).value["queues"]).to contain_exactly "default"
        end
      end

      context 'with job_class' do
        it 'inserts values into a json array' do
          expect(described_class.where(key: described_class::PAUSES).count).to eq 0

          described_class.pause(job_class: "MyJob")
          expect(described_class.where(key: described_class::PAUSES).count).to eq 1
          expect(described_class.find_by(key: described_class::PAUSES).value["job_classes"]).to contain_exactly "MyJob"

          described_class.pause(job_class: "AnotherJob")
          expect(described_class.where(key: described_class::PAUSES).count).to eq 1
          expect(described_class.find_by(key: described_class::PAUSES).value["job_classes"]).to contain_exactly "MyJob", "AnotherJob"

          described_class.unpause(job_class: "MyJob")
          described_class.unpause(job_class: "AnotherJob")
          expect(described_class.find_by(key: described_class::PAUSES).value["job_classes"]).to eq []
        end

        it 'does not insert duplicate job classes' do
          described_class.pause(job_class: "MyJob")
          described_class.pause(job_class: "MyJob")
          expect(described_class.where(key: described_class::PAUSES).count).to eq 1
          expect(described_class.find_by(key: described_class::PAUSES).value["job_classes"]).to contain_exactly "MyJob"
        end
      end
    end

    describe '.unpause' do
      it 'raises ArgumentError if neither queue nor job_class is provided' do
        expect { described_class.unpause }.to raise_error(ArgumentError, "Must provide either queue or job_class, but not both")
      end

      it 'raises ArgumentError if both queue and job_class are provided' do
        expect { described_class.unpause(queue: "default", job_class: "MyJob") }.to raise_error(ArgumentError, "Must provide either queue or job_class, but not both")
      end

      context 'with queue' do
        it 'safely handles non-existent settings' do
          expect { described_class.unpause(queue: "default") }.not_to raise_error
        end

        it 'removes the queue from the paused list' do
          described_class.pause(queue: "default")
          described_class.pause(queue: "mailers")
          expect(described_class.find_by(key: described_class::PAUSES).value["queues"]).to contain_exactly "default", "mailers"

          described_class.unpause(queue: "default")
          expect(described_class.find_by(key: described_class::PAUSES).value["queues"]).to contain_exactly "mailers"
        end
      end

      context 'with job_class' do
        it 'safely handles non-existent settings' do
          expect { described_class.unpause(job_class: "MyJob") }.not_to raise_error
        end

        it 'removes the job class from the paused list' do
          described_class.pause(job_class: "MyJob")
          described_class.pause(job_class: "AnotherJob")
          expect(described_class.find_by(key: described_class::PAUSES).value["job_classes"]).to contain_exactly "MyJob", "AnotherJob"

          described_class.unpause(job_class: "MyJob")
          expect(described_class.find_by(key: described_class::PAUSES).value["job_classes"]).to contain_exactly "AnotherJob"
        end
      end
    end

    describe '.paused?' do
      it 'raises ArgumentError if both queue and job_class are provided' do
        expect { described_class.paused?(queue: "default", job_class: "MyJob") }.to raise_error(ArgumentError, "Must provide either queue or job_class, or neither")
      end

      it 'returns true when queue is paused' do
        described_class.pause(queue: "default")
        expect(described_class.paused?(queue: "default")).to be true
      end

      it 'returns false when queue is not paused' do
        expect(described_class.paused?(queue: "default")).to be false
      end

      it 'returns true when job class is paused' do
        described_class.pause(job_class: "MyJob")
        expect(described_class.paused?(job_class: "MyJob")).to be true
      end

      it 'returns false when job class is not paused' do
        expect(described_class.paused?(job_class: "MyJob")).to be false
      end
    end

    describe '.paused' do
      it 'returns empty arrays when nothing is paused' do
        expect(described_class.paused).to eq({ queues: [], job_classes: [] })
      end

      it 'returns only queues when type is :queues' do
        described_class.pause(queue: "default")
        described_class.pause(job_class: "MyJob")
        expect(described_class.paused(:queues)).to contain_exactly "default"
      end

      it 'returns only job classes when type is :job_classes' do
        described_class.pause(queue: "default")
        described_class.pause(job_class: "MyJob")
        expect(described_class.paused(:job_classes)).to contain_exactly "MyJob"
      end

      it 'returns both queues and job classes by default' do
        described_class.pause(queue: "default")
        described_class.pause(job_class: "MyJob")
        expect(described_class.paused).to eq({
                                               queues: ["default"],
          job_classes: ["MyJob"],
                                             })
      end
    end
  end
end
