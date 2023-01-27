# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::Notifier do
  describe '.instances' do
    it 'contains all registered instances' do
      notifier = nil
      expect do
        notifier = described_class.new(enable_listening: true)
      end.to change { described_class.instances.size }.by(1)

      expect(described_class.instances).to include notifier
    end
  end

  describe '.notify' do
    it 'sends a message to Postgres' do
      expect { described_class.notify("hello") }.not_to raise_error
    end
  end

  describe '#connected?' do
    it 'becomes true when the notifier is connected' do
      notifier = described_class.new(enable_listening: true)
      sleep_until(max: 5, increments_of: 0.5) { notifier.connected? }

      expect do
        notifier.shutdown
      end.to change(notifier, :connected?).from(true).to(false)
    end
  end

  describe '#listen' do
    it 'loops until it receives a command' do
      stub_const 'RECEIVED_MESSAGE', Concurrent::AtomicBoolean.new(false)

      recipient = proc { |_payload| RECEIVED_MESSAGE.make_true }

      notifier = described_class.new(recipient, enable_listening: true)
      sleep_until(max: 5, increments_of: 0.5) { notifier.listening? }
      described_class.notify(true)
      sleep_until(max: 5, increments_of: 0.5) { RECEIVED_MESSAGE.true? }
      notifier.shutdown

      expect(RECEIVED_MESSAGE.true?).to be true
    end

    it 'loops but does not receive a command if listening is not enabled' do
      stub_const 'RECEIVED_MESSAGE', Concurrent::AtomicBoolean.new(false)

      recipient = proc { |_payload| RECEIVED_MESSAGE.make_true }
      notifier = described_class.new(recipient, enable_listening: false)
      expect(notifier.listening?).to be false
      described_class.notify(true)
      sleep_until(max: 1, increments_of: 0.5) { RECEIVED_MESSAGE.false? }
      notifier.shutdown

      expect(RECEIVED_MESSAGE.false?).to be true
    end

    it 'raises exception to GoodJob.on_thread_error' do
      stub_const('ExpectedError', Class.new(StandardError))
      on_thread_error = instance_double(Proc, call: nil)
      allow(GoodJob).to receive(:on_thread_error).and_return(on_thread_error)
      allow(JSON).to receive(:parse).and_raise ExpectedError

      notifier = described_class.new(enable_listening: true)
      sleep_until(max: 5, increments_of: 0.5) { notifier.listening? }

      described_class.notify(true)
      wait_until(max: 5, increments_of: 0.5) { expect(on_thread_error).to have_received(:call).at_least(:once).with instance_of(ExpectedError) }

      notifier.shutdown
    end

    it 'raises exception to GoodJob.on_thread_error when there is a connection error' do
      stub_const('ExpectedError', Class.new(ActiveRecord::ConnectionNotEstablished))
      stub_const('GoodJob::Notifier::CONNECTION_ERRORS_REPORTING_THRESHOLD', 1)
      on_thread_error = instance_double(Proc, call: nil)
      allow(GoodJob).to receive(:on_thread_error).and_return(on_thread_error)
      allow(JSON).to receive(:parse).and_raise ExpectedError

      notifier = described_class.new(enable_listening: true)
      sleep_until(max: 5, increments_of: 0.5) { notifier.listening? }

      described_class.notify(true)
      wait_until(max: 5, increments_of: 0.5) { expect(on_thread_error).to have_received(:call).at_least(:once).with instance_of(ExpectedError) }

      notifier.shutdown
    end
  end

  describe 'Process tracking' do
    it 'creates and destroys a new Process record' do
      notifier = described_class.new(enable_listening: true)

      wait_until { expect(GoodJob::Process.count).to eq 1 }

      process = GoodJob::Process.first
      expect(process.id).to eq GoodJob::Process.current_id
      expect(process).to be_advisory_locked

      notifier.shutdown
      expect { process.reload }.to raise_error ActiveRecord::RecordNotFound
    end

    context 'when, for some reason, the process already exists' do
      it 'does not create a new process' do
        process = GoodJob::Process.register
        notifier = described_class.new(enable_listening: true)

        wait_until { expect(notifier).to be_listening }
        expect(GoodJob::Process.count).to eq 1

        notifier.shutdown
        expect(process.reload).to eq process
        process.advisory_unlock
      end
    end
  end
end
