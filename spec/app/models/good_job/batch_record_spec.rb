# frozen_string_literal: true
require 'rails_helper'

describe GoodJob::BatchRecord do
  before do
    stub_const 'TestJob', Class.new(ActiveJob::Base)
    TestJob.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
  end

  describe '.enqueue' do
    it 'creates a batch' do
      record = described_class.enqueue do
        TestJob.perform_later
        TestJob.perform_later
      end

      expect(record).to be_persisted
      expect(record.enqueued_at).to be_within(1.second).of(Time.current)
      expect(record.jobs.count).to eq 2
    end
  end

  describe '#add' do
    let(:record) { described_class.new }

    it 'preserves the batch' do
      record.add do
        TestJob.perform_later
        TestJob.perform_later
      end

      expect(record).to be_persisted
      expect(record.jobs.count).to eq 2
    end
  end

  describe '#enqueue' do
    let(:record) { described_class.new }

    it 'marks the job as enqueued' do
      record.enqueue do
        TestJob.perform_later
        TestJob.perform_later
      end

      expect(record.jobs.count).to eq 2
      expect(record.enqueued_at).to be_present
    end

    it 'can be used without a block' do
      expect { record.enqueue }.to change(record, :enqueued_at).from(nil)
    end

    it 'does not overwrite an old value' do
      record.enqueued_at = 1.day.ago
      expect { record.enqueue }.not_to change(record, :enqueued_at)
    end

    it 'can assign the callback job' do
      record = described_class.new
      record.enqueue(TestJob)

      expect(record.callback_job_class).to eq "TestJob"
    end
  end

  describe '#properties' do
    it 'serializes and deserializes values' do
      batch = described_class.create(properties: { foo: 'bar' })
      reloaded_batch = described_class.find(batch.id)

      expect(reloaded_batch.properties).to eq({ foo: 'bar' })
    end

    it 'can modify values and they are saved' do
      batch = described_class.create(properties: { foo: 'bar' })
      batch.properties[:foo] = 'baz'
      batch.save!

      reloaded_batch = described_class.find(batch.id)
      expect(reloaded_batch.properties).to eq({ foo: 'baz' })
      reloaded_batch.properties[:foo] = 'quz'
      reloaded_batch.save!

      batch.reload
      expect(batch.properties).to eq({ foo: 'quz' })
      batch.properties = {}
      batch.save!

      reloaded_batch.reload
      expect(reloaded_batch.properties).to eq({})
    end
  end
end
