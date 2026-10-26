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

    it 'wakes on the socket instead of polling' do
      skip "JRuby polls for messages" if Concurrent.on_jruby?
      stub_const("GoodJob::Notifier::WAIT_INTERVAL", 60)
      stub_const("GoodJob::DedicatedConnection::KEEPALIVE_INTERVAL", 60)
      event = Concurrent::Event.new
      notifier = described_class.new(proc { |_payload| event.set }, enable_listening: true)
      expect(notifier.listening?(timeout: 5)).to be true

      described_class.notify(true)
      expect(event.wait(1)).to be true

      notifier.shutdown
    end

    it 'receives messages buffered by other queries on the connection' do
      event = Concurrent::Event.new
      notifier = described_class.new(proc { |_payload| event.set }, enable_listening: true)
      expect(notifier.listening?(timeout: 5)).to be true
      connection = notifier.instance_variable_get(:@connection)

      # Hold the reactor thread so the message arrives while a query is running, not while waiting on the socket.
      connection.post do |conn|
        described_class.notify(true)
        conn.raw_connection.async_exec("SELECT pg_sleep(0.2)")
      end.value!
      expect(event.wait(1)).to be true

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

    shared_examples 'renews the process on every tick' do
      specify do
        refreshes = Concurrent::AtomicFixnum.new(0)
        allow(GoodJob.capsule.tracker).to receive(:renew).and_wrap_original do |original, **kwargs|
          refreshes.increment if kwargs[:connection]
          original.call(**kwargs)
        end

        recipient = proc {}
        notifier = described_class.new(recipient, enable_listening: true)
        expect(notifier).to be_listening(timeout: 2)
        described_class.notify(true)

        wait_until { expect(GoodJob.capsule.tracker.id_for_lock).to be_present }
        wait_until(max: 5) { expect(refreshes.value).to be > 0 }

        notifier.shutdown
      end
    end

    it_behaves_like 'renews the process on every tick'

    context 'with ActiveRecord::Base.logger equal to nil' do
      around do |example|
        logger = ActiveRecord::Base.logger
        ActiveRecord::Base.logger = nil
        example.run
        ActiveRecord::Base.logger = logger
      end

      it_behaves_like 'renews the process on every tick'
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
      stub_const('GoodJob::DedicatedConnection::CONNECTION_ERRORS_REPORTING_THRESHOLD', 1)
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

  describe "#shutdown" do
    it "can be shut down asynchronously" do
      notifier = described_class.new(enable_listening: true)
      wait_until { expect(notifier.listening?).to be true }
      notifier.shutdown(timeout: nil)
      wait_until { expect(notifier.shutdown?).to be true }
      notifier.shutdown
    end

    it "waits for an asynchronous shutdown when shut down again" do
      notifier = described_class.new(enable_listening: true)
      wait_until { expect(notifier.listening?).to be true }
      notifier.shutdown(timeout: nil)
      expect(notifier.shutdown(timeout: 5)).to be true
      expect(notifier).not_to be_connected
    end
  end

  describe "#restart" do
    it "shuts down and restarts when already running" do
      notifier = described_class.new(enable_listening: true)
      wait_until { expect(notifier.listening?).to be true }
      notifier.restart
      expect(notifier).to be_running
      wait_until { expect(notifier.listening?).to be true }
    end

    it "restarts when shutdown" do
      notifier = described_class.new(enable_listening: true)
      notifier.shutdown
      expect(notifier).to be_shutdown
      notifier.restart
      wait_until { expect(notifier.listening?).to be true }
      notifier.shutdown
    end
  end

  describe "reconnecting" do
    it "replaces a connection that errors and listens again" do
      stub_const("GoodJob::DedicatedConnection::RECONNECT_INTERVAL", 0.1)
      event = Concurrent::Event.new
      recipient = proc { |_payload| event.set }
      notifier = described_class.new(recipient, enable_listening: true)
      expect(notifier.listening?(timeout: 5)).to be true
      first_pid = notifier.instance_variable_get(:@connection).post { |connection| connection.raw_connection.backend_pid }.value!

      GoodJob::Job.connection_pool.with_connection { |connection| connection.execute("SELECT pg_terminate_backend(#{first_pid})") }

      wait_until(max: 5) do
        pid = notifier.instance_variable_get(:@connection).post { |connection| connection.raw_connection.backend_pid }.value
        expect(pid).to be_present
        expect(pid).not_to eq first_pid
      end
      expect(notifier.listening?(timeout: 5)).to be true
      described_class.notify(true)
      expect(event.wait(5)).to be true

      notifier.shutdown
      POSTGRES_NOTICES.clear
    end
  end
end
