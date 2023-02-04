# frozen_string_literal: true
require 'rails_helper'

describe GoodJob::Batch do
  before do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
    stub_const 'TestJob', Class.new(ActiveJob::Base)
  end

  describe '.enqueue' do
    it 'creates a batch' do
      batch = described_class.enqueue do
        TestJob.perform_later
        TestJob.perform_later
      end

      expect(batch).to be_persisted
      expect(batch.enqueued_at).to be_within(1.second).of(Time.current)
      expect(batch.active_jobs.count).to eq 2
    end
  end

  describe '#add' do
    let(:batch) { described_class.new }

    it 'preserves the batch' do
      batch.add do
        TestJob.perform_later
        TestJob.perform_later
      end

      expect(batch).to be_persisted
      expect(batch.active_jobs.count).to eq 2
    end
  end

  describe '#enqueue' do
    let(:batch) { described_class.new }

    it 'marks the job as enqueued' do
      batch.enqueue do
        TestJob.perform_later
        TestJob.perform_later
      end

      expect(batch.active_jobs.count).to eq 2
      expect(batch.enqueued_at).to be_present
    end

    it 'can be used without a block' do
      expect { batch.enqueue }.to change(batch, :enqueued_at).from(nil)
    end

    it 'does not overwrite an old value' do
      batch._record.update(enqueued_at: 1.day.ago)
      expect { batch.enqueue }.not_to change(batch, :enqueued_at)
    end

    it 'can assign callback jobs' do
      batch = described_class.new
      batch.enqueue(on_finish: TestJob, on_success: TestJob, on_discard: TestJob)

      expect(batch.on_finish).to eq "TestJob"
      expect(batch.on_success).to eq "TestJob"
      expect(batch.on_discard).to eq "TestJob"
    end
  end

  describe '#properties' do
    it 'defaults to an empty hash' do
      batch = described_class.new
      expect(batch.properties).to eq({})
    end

    it 'serializes and deserializes values' do
      batch = described_class.new(properties: { foo: 'bar' })
      batch.save
      reloaded_batch = described_class.find(batch.id)

      expect(reloaded_batch.properties).to eq({ foo: 'bar' })
    end

    it 'can modify values and they are saved' do
      batch = described_class.new(foo: 'bar')
      batch.save
      batch.properties[:foo] = 'baz'
      batch.save

      reloaded_batch = described_class.find(batch.id)
      expect(reloaded_batch.properties).to eq({ foo: 'baz' })
      reloaded_batch.properties[:foo] = 'quz'
      reloaded_batch.save

      batch.reload
      expect(batch.properties).to eq({ foo: 'quz' })
      batch.properties.clear
      batch.save

      reloaded_batch.reload
      expect(reloaded_batch.properties).to eq({})
    end

    it 'can serialize GlobalId objects' do
      globalid = GoodJob::Execution.create!

      batch = described_class.new
      batch.save

      batch.properties[:globalid] = globalid
      batch.save
      expect(batch.properties[:globalid]).to eq globalid

      reloaded_batch = described_class.find(batch.id)
      expect(reloaded_batch.properties).to eq({ globalid: globalid })
    end
  end

  describe 'callbacks' do
    before do
      stub_const 'CallbackJob', (Class.new(ActiveJob::Base) do
        def perform(_batch, _options)
          puts "HERE"
        end
      end)
    end

    describe '#on_finish' do
      it 'is enqueued' do
        batch = described_class.new
        batch.on_finish = "CallbackJob"
        batch.enqueue

        expect(batch.callback_active_jobs.size).to eq 1
      end
    end
  end
end
