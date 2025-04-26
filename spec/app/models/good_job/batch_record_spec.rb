# frozen_string_literal: true

require 'rails_helper'

describe GoodJob::BatchRecord do
  before do
    stub_const 'TestJob', Class.new(ActiveJob::Base)
    TestJob.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
  end

  describe '#to_batch' do
    it 'returns a GoodJob::Batch' do
      record = described_class.create!
      batch = record.to_batch

      expect(batch._record).to eq record
      expect(batch.id).to eq record.id
    end
  end

  describe '#display_all' do
    it 'returns all records' do
      first_job = described_class.create(id: '67160140-1bec-4c3b-bc34-1a8b36f87b21')
      second_job = described_class.create(id: '3732d706-fd5a-4c39-b1a5-a9bc6d265811')
      last_job = described_class.create(id: '4fbae77c-6f22-488f-ad42-5bd20f39c28c')

      result = described_class.display_all(after_at: last_job.created_at, after_id: last_job.id)

      expect(result).to eq [second_job, first_job]
    end
  end

  describe '#display_attributes' do
    it 'returns the serialized properties' do
      record = described_class.create(serialized_properties: { 'test' => 'test' })
      expect(record.display_attributes["properties"]).to eq({ 'test' => 'test' })
    end

    context 'when the properties cannot be deserialized' do
      before do
        stub_const 'SomeClass', (Class.new do
          include GlobalID::Identification

          def id
            1
          end

          def self.find(_id)
            new
          end
        end)
      end

      it 'returns the raw value' do
        instance = SomeClass.new
        record = described_class.create(serialized_properties: { 'record' => instance })

        allow(SomeClass).to receive(:find).and_raise(ActiveRecord::RecordNotFound)

        expect(record.display_attributes["properties"]).to eq(
          "_aj_symbol_keys" => [],
          "record" => { "_aj_globalid" => "gid://test-app/SomeClass/1" }
        )
      end
    end
  end

  describe 'implicit sort order' do
    it 'is by created at' do
      first_job = described_class.create(id: '67160140-1bec-4c3b-bc34-1a8b36f87b21')
      described_class.create(id: '3732d706-fd5a-4c39-b1a5-a9bc6d265811')
      last_job = described_class.create(id: '4fbae77c-6f22-488f-ad42-5bd20f39c28c')

      result = described_class.all

      expect(result.first).to eq first_job
      expect(result.last).to eq last_job
    end
  end

  describe 'finished_at' do
    it 'is now set when all jobs in the batch are finished' do
      batch = described_class.create!
      batch.update(enqueued_at: Time.current, jobs_finished_at: Time.current)
      batch.callback_jobs.create!(finished_at: nil)
      batch.callback_jobs.create!(finished_at: Time.current)

      batch._continue_discard_or_finish

      expect(batch.reload.finished_at).to be_nil

      batch.callback_jobs.update(finished_at: Time.current)
      batch._continue_discard_or_finish

      expect(batch.reload.finished_at).to be_within(1.second).of(Time.current)
    end
  end

  describe 'deletion logic' do
    it 'checks finished_at' do
      batch = described_class.create!
      batch.update(enqueued_at: Time.current, jobs_finished_at: Time.current, finished_at: nil)

      expect { described_class.finished_before(Time.current).delete_all }.not_to change(described_class, :count)

      batch.update(finished_at: Time.current)

      expect { described_class.finished_before(Time.current).delete_all }.to change(described_class, :count).by(-1)
    end
  end
end
