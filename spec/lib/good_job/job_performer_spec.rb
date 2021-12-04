# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::JobPerformer do
  describe '#name' do
    it 'displays the queues' do
      queue_string = 'mice, elephants'
      job_performer = described_class.new(queue_string)
      expect(job_performer.name).to eq queue_string
    end
  end

  describe '#next' do
    it 'calls GoodJob.perform_with_advisory_lock' do
      allow(GoodJob::Execution).to receive(:perform_with_advisory_lock)

      job_performer = described_class.new('*')
      job_performer.next

      expect(GoodJob::Execution).to have_received(:perform_with_advisory_lock)
    end
  end

  describe 'next?' do
    it 'filters on queue name' do
      state = { queue_name: 'elephants' }

      result = described_class.new('*').next?(state)
      expect(result).to eq true

      result = described_class.new('elephants').next?(state)
      expect(result).to eq true

      result = described_class.new('-elephants').next?(state)
      expect(result).to eq false

      result = described_class.new('mice').next?(state)
      expect(result).to eq false
    end
  end

  describe '#cleanup' do
    it 'calls GoodJob.cleanup_preserved_jobs' do
      allow(GoodJob).to receive(:cleanup_preserved_jobs)
      described_class.new('*').cleanup
      expect(GoodJob).to have_received(:cleanup_preserved_jobs)
    end
  end
end
