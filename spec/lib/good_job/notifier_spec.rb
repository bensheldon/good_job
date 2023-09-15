# frozen_string_literal: true

require 'rails_helper'
require 'concurrent/executor/fixed_thread_pool'

RSpec.describe GoodJob::Notifier do
  describe '.instances' do
    it 'contains all registered instances' do
      notifier = nil
      expect do
        notifier = described_class.new(enable_listening: true)
      end.to change { described_class.instances.size }.by(1)

      expect(described_class.instances).to include notifier
      sleep 1
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
      expect(notifier.connected?(timeout: 5)).to be true

      expect do
        notifier.shutdown
      end.to change(notifier, :connected?).from(true).to(false)
    end

    it 'remains true through multiple connection errors until CONNECTION_ERRORS_REPORTING_THRESHOLD is reached' do
      error_event = Concurrent::Event.new
      allow(GoodJob).to receive(:_on_thread_error) { error_event.set }

      stub_const('GoodJob::Notifier::WAIT_INTERVAL', 0.1)
      stub_const('GoodJob::Notifier::RECONNECT_INTERVAL', 0.1)
      stub_const('GoodJob::Notifier::CONNECTION_ERRORS_REPORTING_THRESHOLD', 3)

      notifier = described_class.new(enable_listening: true)
      expect(notifier.connected?(timeout: 5)).to be true
      allow(notifier).to receive(:wait_for_notify).and_raise(ActiveRecord::ConnectionTimeoutError)
      error_event.wait(5)
      expect(notifier).not_to be_connected
    end
  end

  describe '#listen' do
    it 'loops until it receives a command' do
      event = Concurrent::Event.new
      recipient = proc { |_payload| event.set }

      notifier = described_class.new(recipient, enable_listening: true)
      notifier.listening?(timeout: 5)

      described_class.notify(true)
      expect(event.wait(5)).to be true

      notifier.shutdown
    end

    it 'loops but does not receive a command if listening is not enabled' do
      latch = Concurrent::CountDownLatch.new(1)
      recipient = proc { |_payload| latch.count_down }
      notifier = described_class.new(recipient, enable_listening: false)

      expect(notifier.connected?(timeout: 5)).to be true
      expect(notifier.listening?(timeout: 1)).to be false
      sleep 1
      notifier.shutdown

      expect(latch.count).to eq 1
    end

    shared_examples 'calls refresh_if_stale on every tick' do
      specify do
        refreshes = Concurrent::AtomicFixnum.new(0)
        allow_any_instance_of(GoodJob::Process).to receive(:refresh_if_stale) { refreshes.increment }

        recipient = proc {}
        notifier = described_class.new(recipient, enable_listening: true)
        expect(notifier).to be_listening(timeout: 2)
        described_class.notify(true)

        wait_until(max: 5) { expect(refreshes.value).to be > 0 }

        notifier.shutdown
      end
    end

    it_behaves_like 'calls refresh_if_stale on every tick'

    context 'with ActiveRecord::Base.logger equal to nil' do
      around do |example|
        logger = ActiveRecord::Base.logger
        ActiveRecord::Base.logger = nil
        example.run
        ActiveRecord::Base.logger = logger
      end

      it_behaves_like 'calls refresh_if_stale on every tick'
    end

    it 'raises exception to GoodJob.on_thread_error' do
      stub_const('ExpectedError', Class.new(StandardError))
      on_thread_error = instance_double(Proc, call: nil)
      allow(GoodJob).to receive(:on_thread_error).and_return(on_thread_error)
      allow(JSON).to receive(:parse).and_raise ExpectedError

      notifier = described_class.new(enable_listening: true)
      expect(notifier).to be_listening(timeout: 2)

      described_class.notify(true)
      wait_until { expect(on_thread_error).to have_received(:call).at_least(:once).with instance_of(ExpectedError) }

      notifier.shutdown
    end

    it 'raises exception to GoodJob.on_thread_error when there is a connection error' do
      stub_const('ExpectedError', Class.new(ActiveRecord::ConnectionNotEstablished))
      stub_const('GoodJob::Notifier::CONNECTION_ERRORS_REPORTING_THRESHOLD', 1)
      on_thread_error = instance_double(Proc, call: nil)
      allow(GoodJob).to receive(:on_thread_error).and_return(on_thread_error)
      allow(JSON).to receive(:parse).and_raise ExpectedError

      notifier = described_class.new(enable_listening: true)
      expect(notifier).to be_listening(timeout: 2)

      described_class.notify(true)
      wait_until { expect(on_thread_error).to have_received(:call).at_least(:once).with instance_of(ExpectedError) }

      notifier.shutdown
    end
  end

  describe '#shutdown' do
    let(:executor) { Concurrent::FixedThreadPool.new(1) }

    it 'shuts down when the thread is killed' do
      notifier = described_class.new(executor: executor, enable_listening: true)
      wait_until { expect(notifier).to be_listening }
      executor.kill
      wait_until { expect(notifier).not_to be_listening }
      notifier.shutdown
      expect(notifier).to be_shutdown
    end
  end

  describe '#restart' do
    let(:executor) { Concurrent::FixedThreadPool.new(1) }

    it 'shuts down and restarts when already running' do
      notifier = described_class.new(executor: executor, enable_listening: true)
      wait_until { expect(notifier).to be_listening }
      notifier.restart
      expect(notifier).to be_running
    end

    it 'restarts when shutdown' do
      notifier = described_class.new(executor: executor, enable_listening: true)
      notifier.shutdown
      expect(notifier).to be_shutdown
      notifier.restart
      wait_until { expect(notifier).to be_listening }
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
