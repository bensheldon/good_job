# frozen_string_literal: true

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
      latch = Concurrent::CountDownLatch.new(3)

      payloads = []
      callback = proc { |*args| payloads << args }

      ActiveSupport::Notifications.subscribed(callback, "finished_timer_task") do
        recipient = proc { |_payload| latch.count_down }
        poller = described_class.new(recipient, poll_interval: 0.1)
        latch.wait(10)
        poller.shutdown
      end

      expect(payloads.size).to be >= 1
    end
  end

  describe '#recipients' do
    it 'polls recipients method' do
      latch = Concurrent::CountDownLatch.new(3)

      recipient = proc { |_payload| latch.count_down }
      poller = described_class.new(recipient, poll_interval: 0.1)

      expect(latch.wait(10)).to eq true

      poller.shutdown
    end
  end
end
