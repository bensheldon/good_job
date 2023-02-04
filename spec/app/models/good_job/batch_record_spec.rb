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
end
