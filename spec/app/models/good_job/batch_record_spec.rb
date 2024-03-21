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
end
