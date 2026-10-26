# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::ProcessHeartbeat do
  it 'keeps the process registered when the connection is replaced' do
    connection = GoodJob::DedicatedConnection.new(retirement_age: 0.5)
    described_class.new(connection: connection)
    notifier = GoodJob::Notifier.new(connection: connection)
    connection.start
    expect(notifier.listening?(timeout: 5)).to be true
    wait_until { expect(GoodJob.capsule.tracker.locks).to eq 1 }
    process_id = GoodJob.capsule.tracker.id_for_lock
    first_pid = connection.post { |conn| conn.raw_connection.backend_pid }.value!

    wait_until(max: 5) { expect(connection.post { |conn| conn.raw_connection.backend_pid }.value!).not_to eq first_pid }
    expect(notifier).to be_listening
    expect(GoodJob.capsule.tracker.locks).to eq 1
    expect(GoodJob.capsule.tracker.id_for_lock).to eq process_id

    connection.shutdown
    expect(GoodJob.capsule.tracker.locks).to eq 0
  end

  it 'refreshes a stale process record on the dedicated connection, using a pooled connection only for cleanup' do
    connection = GoodJob::DedicatedConnection.new
    heartbeat = described_class.new(connection: connection)
    connection.start
    wait_until { expect(GoodJob.capsule.tracker.locks).to eq 1 }
    # Without the advisory lock heartbeat, the record is created on first use.
    GoodJob.capsule.tracker.id_for_lock
    record = GoodJob.capsule.tracker.record
    GoodJob::Process.where(id: record.id).update_all(updated_at: 1.hour.ago) # rubocop:disable Rails/SkipsModelValidations
    record.updated_at = 1.hour.ago
    allow(GoodJob::Process).to receive(:cleanup)

    checkouts = Concurrent::AtomicFixnum.new(0)
    allow(GoodJob::Process.connection_pool).to receive(:checkout).and_wrap_original do |original, *args|
      checkouts.increment if Thread.current.name == "good_job-reactor"
      original.call(*args)
    end

    connection.post { |conn| heartbeat.refresh_process(conn) }.value!
    expect(GoodJob::Process.find(record.id).updated_at).to be > 1.minute.ago
    expect(GoodJob::Process).to have_received(:cleanup).once
    expect(checkouts.value).to eq 1

    # Not stale: neither refreshes nor checks out a pooled connection
    connection.post { |conn| heartbeat.refresh_process(conn) }.value!
    expect(GoodJob::Process).to have_received(:cleanup).once
    expect(checkouts.value).to eq 1
    connection.shutdown
  end

  it 'registers again on a new connection when deregistering the faulted one failed' do
    tracker = instance_spy(GoodJob::CapsuleTracker)
    allow(tracker).to receive(:unregister).and_raise(ActiveRecord::ConnectionNotEstablished)
    heartbeat = described_class.allocate
    heartbeat.instance_variable_set(:@capsule, Struct.new(:tracker).new(tracker))

    heartbeat.register_process(:first)
    expect { heartbeat.deregister_process(:first) }.to raise_error(ActiveRecord::ConnectionNotEstablished)
    heartbeat.register_process(:second)

    expect(tracker).to have_received(:register).with(hash_including(advisory_lock_connection: :second))
  end

  it 'creates and destroys a new Process record' do
    notifier = GoodJob::Notifier.new(enable_listening: true)

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
        heartbeat = described_class.allocate
        heartbeat.instance_variable_set(:@capsule, Struct.new(:tracker).new(tracker))
        heartbeat.instance_variable_set(:@advisory_lock_heartbeat, true)
        heartbeat.instance_variable_set(:@process_registered, true)
        heartbeat.deregister_process(lock_connection)
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
      heartbeat = described_class.allocate
      heartbeat.instance_variable_set(:@advisory_lock_heartbeat, true)
      heartbeat.instance_variable_set(:@capsule, Struct.new(:tracker).new(tracker))
      pool = GoodJob::Process.connection_pool
      allow(pool).to receive(:with_connection).and_raise(ActiveRecord::ConnectionTimeoutError)

      expect { heartbeat.register_process(nil) }.to raise_error(ActiveRecord::ConnectionTimeoutError)
      # The connection is disconnected, and deregistration attempted, even when registration fails.
      expect { heartbeat.deregister_process(nil) }.not_to raise_error
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
      heartbeat = described_class.allocate
      heartbeat.instance_variable_set(:@advisory_lock_heartbeat, true)
      heartbeat.instance_variable_set(:@capsule, Struct.new(:tracker).new(tracker))
      heartbeat.register_process(nil)
      expect(tracker.locks).to eq 2

      heartbeat.deregister_process(nil)
      heartbeat.deregister_process(nil)
      expect(tracker.locks).to eq 1
    ensure
      tracker&.unregister
    end

    it 'skips cleanup on a checkout timeout without unregistering the process' do
      heartbeat = described_class.allocate
      heartbeat.instance_variable_set(:@advisory_lock_heartbeat, true)
      tracker = instance_spy(GoodJob::CapsuleTracker, renew: true)
      heartbeat.instance_variable_set(:@capsule, Struct.new(:tracker).new(tracker))
      allow(GoodJob::Process).to receive(:cleanup)
      allow(GoodJob::Process.connection_pool).to receive(:with_connection).and_raise(ActiveRecord::ConnectionTimeoutError)
      expect { heartbeat.refresh_process(nil) }.not_to raise_error
      expect(tracker).to have_received(:renew).with(connection: nil)
      expect(GoodJob::Process).not_to have_received(:cleanup)
      expect(tracker).not_to have_received(:unregister)
    ensure
      allow(GoodJob::Process.connection_pool).to receive(:with_connection).and_call_original
    end

    it 'does not retry a timeout raised after deregistration starts' do
      heartbeat = described_class.allocate
      heartbeat.instance_variable_set(:@advisory_lock_heartbeat, true)
      heartbeat.instance_variable_set(:@process_registered, true)
      tracker = instance_double(GoodJob::CapsuleTracker)
      heartbeat.instance_variable_set(:@capsule, Struct.new(:tracker).new(tracker))
      allow(tracker).to receive(:unregister).and_raise(ActiveRecord::ConnectionTimeoutError)

      expect { heartbeat.deregister_process(nil) }.to raise_error(ActiveRecord::ConnectionTimeoutError)
      expect(tracker).to have_received(:unregister).once
    end

    it 'takes an advisory lock on the process record' do
      notifier = GoodJob::Notifier.new(enable_listening: true)

      wait_until { expect(GoodJob::Process.count).to eq 1 }

      process = GoodJob::Process.first
      expect(process.id).to eq GoodJob.capsule.tracker.id_for_lock

      notifier.shutdown
      expect { process.reload }.to raise_error ActiveRecord::RecordNotFound
    end
  end
end
