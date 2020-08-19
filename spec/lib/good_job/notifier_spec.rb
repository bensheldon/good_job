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

  describe '#listen' do
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
  end
end
