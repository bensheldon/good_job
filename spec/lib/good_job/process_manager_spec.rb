# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::ProcessManager do
  let!(:process_manager) { described_class.new }

  describe '#initialize' do
    it 'creates a timer and registers the process implicitly' do
      expect(process_manager.timer).to be_a Concurrent::TimerTask

      process = GoodJob::Process.first
      expect(process).to be_present
      expect(process.id).to eq described_class.current_process_id
    end
  end

  describe 'heartbeats' do
    it 'updates the process record every HEARTBEAT_INTERVAL' do
      stub_const('GoodJob::ProcessManager::HEARTBEAT_INTERVAL', 0.5)
      described_class.new

      wait_until(max: 5, increments_of: 0.5) do
        process = GoodJob::Process.find_by(id: described_class.current_process_id)
        expect(process.updated_at).to be > process.created_at + 1.second
      end
    end
  end

  describe '#shutdown' do
    it 'unregisters the process' do
      expect { process_manager.shutdown }.to change { GoodJob::Process.find_by(id: described_class.current_process_id) }.to be_nil
    end
  end
end
