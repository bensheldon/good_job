# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::CapsuleRecord do
  describe 'Scopes' do
    describe '.active' do
      it 'returns active processes' do
        expect(described_class.active.count).to eq 0
      end
    end

    describe '.inactive' do
      it 'returns inactive processes' do
        expect(described_class.inactive.count).to eq 0
      end
    end
  end

  describe '.process_state' do
    it 'contains information about the process' do
      expect(described_class.process_state).to include(
        database_connection_pool: include(
          size: be_an(Integer),
          active: be_an(Integer)
        )
      )
    end
  end

  describe '#basename' do
    let(:process) { described_class.new state: {} }

    it 'splits proctitle on dir and program name' do
      process.state['proctitle'] = '/app/bin/good_job'
      expect(process.basename).to eq('good_job')
    end

    it 'preserves program arguments' do
      process.state['proctitle'] = '/Users/me/projects/good_job/bin/bundle exec rails start'
      expect(process.basename).to eq('bundle exec rails start')
    end
  end

  describe '#refresh' do
    it 'updates the record' do
      process = described_class.create! state: {}, updated_at: 1.day.ago
      expect do
        expect(process.refresh).to be true
      end.to change(process, :updated_at).to within(1.second).of(Time.current)
    end

    context 'when the record has been deleted elsewhere' do
      it 'creates a new record' do
        process = described_class.create! state: {}, updated_at: 1.day.ago
        described_class.where(id: process.id).delete_all

        expect { process.refresh }.to change(described_class, :count).from(0).to(1)
      end
    end
  end

  describe '#stale?' do
    it 'returns true when the record is stale' do
      process = described_class.create! state: {}, updated_at: 1.day.ago
      expect(process.stale?).to be true
      process.refresh
      expect(process.stale?).to be false
    end
  end

  describe '#expired?' do
    it 'returns true when the record is stale' do
      process = described_class.create! state: {}, updated_at: 1.day.ago
      expect(process.expired?).to be true
      process.refresh
      expect(process.expired?).to be false
    end
  end
end
