# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::Process do
  describe '.current_id' do
    it 'returns a uuid that does not change' do
      value = described_class.current_id
      expect(value).to be_present

      expect(described_class.current_id).to eq value
    end

    it 'changes when the PID changes' do
      allow(Process).to receive(:pid).and_return(1)
      original_value = described_class.current_id

      allow(Process).to receive(:pid).and_return(2)
      expect(described_class.current_id).not_to eq original_value

      # Unstub the pid or RSpec/DatabaseCleaner may fail
      RSpec::Mocks.space.proxy_for(Process).reset
    end
  end

  describe '.register' do
    it 'registers the process' do
      process = nil
      expect do
        process = described_class.register
      end.to change(described_class, :count).by(1)

      process.deregister
    end

    context 'when there is already an existing record' do
      it 'returns nil' do
        described_class.create!(id: described_class.current_id)
        expect(described_class.register).to be_nil
      end
    end
  end

  describe '#deregister' do
    it 'deregisters the record' do
      process = described_class.register
      expect { process.deregister }.to change(described_class, :count).by(-1)
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
end
