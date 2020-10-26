require 'rails_helper'

RSpec.describe GoodJob::Notifier do
  describe '.instances' do
    it 'contains all registered instances' do
      notifier = nil
      expect do
        notifier = described_class.new
      end.to change { described_class.instances.size }.by(1)

      expect(described_class.instances).to include notifier
    end
  end

  describe '.notify' do
    it 'sends a message to Postgres' do
      described_class.notify("hello")
    end
  end

  describe '#listen', skip_if_java: true do
    it 'loops until it receives a command' do
      stub_const 'RECEIVED_MESSAGE', Concurrent::AtomicBoolean.new(false)

      recipient = proc { |_payload| RECEIVED_MESSAGE.make_true }

      notifier = described_class.new(recipient)
      sleep_until(max: 5, increments_of: 0.5) { notifier.listening? }
      described_class.notify(true)
      sleep_until(max: 5, increments_of: 0.5) { RECEIVED_MESSAGE.true? }
      notifier.shutdown

      expect(RECEIVED_MESSAGE.true?).to eq true
    end

    it 'raises exception to GoodJob.on_thread_error' do
      stub_const('ExpectedError', Class.new(StandardError))
      on_thread_error = instance_double(Proc, call: nil)
      allow(GoodJob).to receive(:on_thread_error).and_return(on_thread_error)
      allow(JSON).to receive(:parse).and_raise ExpectedError

      notifier = described_class.new
      sleep_until(max: 5, increments_of: 0.5) { notifier.listening? }
      described_class.notify(true)
      notifier.shutdown

      expect(on_thread_error).to have_received(:call).at_least(:once).with instance_of(ExpectedError)
    end
  end
end
