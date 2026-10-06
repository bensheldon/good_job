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

        wait_until { expect(GoodJob.capsule.tracker.id_for_lock).to be_present }
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

    it 'executes a noop SQL query every 10 seconds to keep the connection alive' do
      stub_const("GoodJob::Notifier::KEEPALIVE_INTERVAL", 0.1)
      stub_const("GoodJob::Notifier::WAIT_INTERVAL", 0.1)

      notifier = described_class.new(enable_listening: true)
      original_keepalive = notifier.instance_variable_get(:@last_keepalive_time)

      expect(notifier).to be_listening(timeout: 2)
      wait_until { expect(notifier.instance_variable_get(:@last_keepalive_time)).to be > original_keepalive }

      notifier.shutdown
    end
  end

  describe '#shutdown' do
    let(:executor) { Concurrent::FixedThreadPool.new(1) }

    it 'shuts down when the thread is killed' do
      skip "Thread#kill does not reliably terminate JRuby threads" if Concurrent.on_jruby?

      notifier = described_class.new(executor: executor, enable_listening: true)
      wait_until { expect(notifier).to be_listening }
      executor.kill
      wait_until { expect(notifier).not_to be_listening }
      notifier.shutdown
      expect(notifier).to be_shutdown
    end

    it 'can be shut down asynchronously' do
      notifier = described_class.new(executor: executor, enable_listening: true)
      wait_until { expect(notifier).to be_listening }
      notifier.shutdown(timeout: nil)
      wait_until { expect(notifier).to be_shutdown }
      notifier.shutdown
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

      wait_until { expect(GoodJob.capsule.tracker.locks).to eq 1 }

      # Process record won't be created until the first lock is acquired when not advisory locked
      id_for_lock = GoodJob.capsule.tracker.id_for_lock
      process = GoodJob::Process.first
      expect(process.id).to eq id_for_lock
      expect(process).not_to be_advisory_locked

      notifier.shutdown
      expect { process.reload }.to raise_error ActiveRecord::RecordNotFound
    end

    context 'when advisory_lock_heartbeat is true' do
      before do
        allow(GoodJob.configuration).to receive(:advisory_lock_heartbeat).and_return(true)
      end

      it 'preserves the advisory lock across a checkout timeout and lets jobs return connections while waiting to unregister' do
        pool = GoodJob::Process.connection_pool
        lock_connection = pool.checkout
        pool.remove(lock_connection)
        tracker = GoodJob::CapsuleTracker.new(executor: nil)
        tracker.register(with_advisory_lock: true, advisory_lock_connection: lock_connection)
        job_ready = Concurrent::Event.new
        finish_job = Concurrent::Event.new
        job_finished = Concurrent::Event.new
        waiting_for_connection = Concurrent::Event.new
        held_connections = []

        job_thread = Thread.new do
          pool.with_connection do
            tracker.register
            job_ready.set
            finish_job.wait
            tracker.unregister
          end
          job_finished.set
        end
        expect(job_ready.wait(5)).to be true
        held_connections << pool.checkout while pool.stat[:busy] < pool.size

        checkout_attempts = 0
        allow(pool).to receive(:checkout).and_wrap_original do |original, *args|
          if checkout_attempts < 2
            expect(tracker.record.lock_type).to eq('advisory')
            expect(PgLock.advisory_lock_details_for(lock_connection)).not_to be_empty
            checkout_attempts += 1
          end
          unless waiting_for_connection.set?
            waiting_for_connection.set
            raise ActiveRecord::ConnectionTimeoutError
          end
          waiting_for_connection.set
          original.call(*args)
        end
        notifier_thread = Thread.new do
          notifier = described_class.allocate
          notifier.instance_variable_set(:@capsule, Struct.new(:tracker).new(tracker))
          notifier.instance_variable_set(:@advisory_lock_heartbeat, true)
          notifier.instance_variable_set(:@process_registered, true)
          notifier.connection = lock_connection
          notifier.deregister_process
        ensure
          notifier.connection = nil
        end

        expect(waiting_for_connection.wait(5)).to be true
        finish_job.set
        expect(job_finished.wait(2)).to be true
        notifier_thread.value
        expect(checkout_attempts).to eq 2
        expect(tracker.locks).to eq 0
        expect(GoodJob::Process.where(id: tracker.process_id)).not_to exist
      ensure
        finish_job&.set
        held_connections&.each { |conn| pool.checkin(conn) }
        job_thread&.join
        notifier_thread&.join
        tracker&.unregister(with_advisory_lock: true, advisory_lock_connection: lock_connection)
        tracker&.unregister
        lock_connection&.disconnect!
      end

      it 'preserves job registrations when notifier registration times out' do
        tracker = GoodJob::CapsuleTracker.new(executor: nil)
        tracker.register
        tracker.register
        process_id = tracker.id_for_lock
        notifier = described_class.allocate
        notifier.instance_variable_set(:@capsule, Struct.new(:tracker).new(tracker))
        pool = GoodJob::Process.connection_pool
        allow(pool).to receive(:with_connection).and_raise(ActiveRecord::ConnectionTimeoutError)

        expect { notifier.register_process }.to raise_error(ActiveRecord::ConnectionTimeoutError)
        # The listen task invokes unlisten callbacks even when registration fails.
        expect { notifier.deregister_process }.not_to raise_error
        expect(tracker.locks).to eq 2

        allow(pool).to receive(:with_connection).and_call_original
        tracker.unregister
        expect(GoodJob::Process.where(id: process_id)).to exist
        expect(tracker.locks).to eq 1
        tracker.unregister
        expect(GoodJob::Process.where(id: process_id)).not_to exist
      ensure
        allow(pool).to receive(:with_connection).and_call_original if pool
        tracker&.unregister
        tracker&.unregister
      end

      it 'unregisters a successful notifier registration only once' do
        tracker = GoodJob::CapsuleTracker.new(executor: nil)
        tracker.register
        notifier = described_class.allocate
        notifier.instance_variable_set(:@capsule, Struct.new(:tracker).new(tracker))
        notifier.register_process
        expect(tracker.locks).to eq 2

        notifier.deregister_process
        notifier.deregister_process
        expect(tracker.locks).to eq 1
      ensure
        tracker&.unregister
      end

      it 'skips a refresh checkout timeout without unregistering the process' do
        notifier = described_class.allocate
        tracker = instance_spy(GoodJob::CapsuleTracker)
        notifier.instance_variable_set(:@capsule, Struct.new(:tracker).new(tracker))
        allow(GoodJob::Process.connection_pool).to receive(:with_connection).and_raise(ActiveRecord::ConnectionTimeoutError)
        expect { notifier.refresh_process }.not_to raise_error
        expect(tracker).not_to have_received(:renew)
        expect(tracker).not_to have_received(:unregister)
      ensure
        allow(GoodJob::Process.connection_pool).to receive(:with_connection).and_call_original
      end

      it 'does not retry a timeout raised after deregistration starts' do
        notifier = described_class.allocate
        notifier.instance_variable_set(:@process_registered, true)
        tracker = instance_double(GoodJob::CapsuleTracker)
        notifier.instance_variable_set(:@capsule, Struct.new(:tracker).new(tracker))
        allow(tracker).to receive(:unregister).and_raise(ActiveRecord::ConnectionTimeoutError)

        expect { notifier.deregister_process }.to raise_error(ActiveRecord::ConnectionTimeoutError)
        expect(tracker).to have_received(:unregister).once
      end

      it 'takes an advisory lock on the process record' do
        notifier = described_class.new(enable_listening: true)

        wait_until { expect(GoodJob::Process.count).to eq 1 }

        process = GoodJob::Process.first
        expect(process.id).to eq GoodJob.capsule.tracker.id_for_lock

        notifier.shutdown
        expect { process.reload }.to raise_error ActiveRecord::RecordNotFound
      end
    end
  end
end
