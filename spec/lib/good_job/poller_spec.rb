require 'rails_helper'

RSpec.describe GoodJob::Poller do
  describe '.instances' do
    it 'contains all registered instances' do
      poller = nil
      expect do
        poller = described_class.new
      end.to change { described_class.instances.size }.by(1)

      expect(described_class.instances).to include poller
    end
  end

  describe '#initialize' do
    it 'accepts a zero or negative poll_interval to disable TimerTask' do
      poller = described_class.new(poll_interval: 0)

      expect(poller.instance_variable_get(:@task)).to be_nil
    end
  end

  describe 'polling' do
    it 'is instrumented' do
      stub_const 'POLL_COUNT', Concurrent::AtomicFixnum.new(0)
      allow(ActiveSupport::Notifications).to receive(:instrument)

      recipient = proc { |_payload| POLL_COUNT.increment }
      poller = described_class.new(recipient, poll_interval: 1)
      sleep_until(max: 5, increments_of: 0.5) { POLL_COUNT.value > 1 }
      poller.shutdown

      expect(ActiveSupport::Notifications).to have_received(:instrument).at_least(:once)
    end
  end

  describe '#recipients' do
    it 'polls recipients method' do
      stub_const 'POLL_COUNT', Concurrent::AtomicFixnum.new(0)
      recipient = proc { |_payload| POLL_COUNT.increment }

      poller = described_class.new(recipient, poll_interval: 1)
      sleep_until(max: 5, increments_of: 0.5) { POLL_COUNT.value > 2 }
      poller.shutdown

      expect(POLL_COUNT.value).to be > 2
    end
  end
end
