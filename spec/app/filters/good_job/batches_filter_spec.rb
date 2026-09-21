# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::BatchesFilter do
  subject(:filter) { described_class.new({}) }

  describe '#records' do
    it 'reuses the same relation for rendering and pagination' do
      GoodJob::BatchRecord.create!

      records = filter.records.load
      filter.records.present?
      filter.next_page_params

      expect(filter.records).to equal(records)
    end
  end

  describe '#job_count' do
    it 'counts jobs for the displayed batches without loading their associations' do
      first_batch = GoodJob::BatchRecord.create!
      second_batch = GoodJob::BatchRecord.create!
      first_batch.jobs.create!
      first_batch.jobs.create!

      displayed_batches = filter.records.load.index_by(&:id)

      expect(filter.job_count(displayed_batches.fetch(first_batch.id))).to eq 2
      expect(filter.job_count(displayed_batches.fetch(second_batch.id))).to eq 0
      expect(displayed_batches.values).to all(satisfy { |batch| !batch.association(:jobs).loaded? })
    end
  end
end
