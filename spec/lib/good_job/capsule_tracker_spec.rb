# frozen_string_literal: true

require 'rails_helper'

describe GoodJob::CapsuleTracker do
  let(:tracker) { described_class.new }

  describe '#register' do
    context 'when used with an advisory lock' do
      it 'creates a Process and sets the lock_type' do
        expect do
          tracker.register(with_advisory_lock: true)
        end.to change(GoodJob::Process, :count).by(1)

        process = GoodJob::Process.last
        expect(process.lock_type).to eq('advisory')

        tracker.unregister(with_advisory_lock: true)

        expect(GoodJob::Process.count).to eq 0
      end

      it 'takes an advisory lock even when process already exists' do
        tracker.register do
          expect(GoodJob::Process.count).to eq 0

          tracker.id_for_lock

          process = GoodJob::Process.last
          expect(process).to be_present
          expect(process).not_to be_advisory_locked
          expect(process.lock_type).to eq(nil)

          tracker.register(with_advisory_lock: true) do
            process.reload
            expect(process).to be_advisory_locked
            expect(process.lock_type).to eq('advisory')
          end

          process.reload
          expect(process).not_to be_advisory_locked
          expect(process.lock_type).to eq(nil)
        end

        expect(GoodJob::Process.count).to eq 0
      end

      it 'increments the number of locks when not used with a block' do
        expect do
          tracker.register(with_advisory_lock: true)
        end.to change(tracker, :locks).by(1)
        tracker.unregister(with_advisory_lock: true)
      end

      it 'tracks multiple locks and advisory locks' do
        tracker.register(with_advisory_lock: true)
        tracker.register
        tracker.register(with_advisory_lock: true)
        tracker.register(with_advisory_lock: true)

        expect(GoodJob::Process.count).to eq 1
        expect(tracker.record.lock_type).to eq('advisory')
        expect(tracker.locks).to eq(4)
        expect(tracker).to be_advisory_locked

        tracker.unregister(with_advisory_lock: true)

        expect(GoodJob::Process.count).to eq 1
        expect(tracker.record.lock_type).to eq(nil)
        expect(tracker.locks).to eq(3)
        expect(tracker).not_to be_advisory_locked

        tracker.unregister(with_advisory_lock: true)
        tracker.unregister
        tracker.unregister(with_advisory_lock: true)

        expect(GoodJob::Process.count).to eq 0
        expect(tracker.locks).to eq(0)
        expect(tracker).not_to be_advisory_locked
      end
    end

    context 'when used with an advisory_lock_connection' do
      # Use explicit checkout so we own the connection lifecycle (lease_connection is sticky and
      # returned to the pool by Rails at unpredictable points, which would leak advisory locks).
      let(:lock_connection) { GoodJob::Process.connection_pool.checkout }

      after { GoodJob::Process.connection_pool.checkin(lock_connection) }

      it 'takes the advisory lock on the specified connection and releases it on unregister' do
        tracker.register(with_advisory_lock: true, advisory_lock_connection: lock_connection)

        process = GoodJob::Process.last
        expect(process.lock_type).to eq('advisory')
        expect(PgLock.advisory_lock_details_for(lock_connection)).not_to be_empty

        tracker.unregister(with_advisory_lock: true, advisory_lock_connection: lock_connection)

        expect(GoodJob::Process.count).to eq 0
        expect(PgLock.advisory_lock_details_for(lock_connection)).to be_empty
      end

      it 'does not release the advisory lock when unregistered with a different connection' do
        other_connection = GoodJob::Process.connection_pool.checkout
        begin
          # Two registrations so the record isn't destroyed when we call unregister once
          tracker.register(with_advisory_lock: true, advisory_lock_connection: lock_connection)
          tracker.register

          process = GoodJob::Process.last
          expect(process.lock_type).to eq('advisory')
          expect(PgLock.advisory_lock_details_for(lock_connection)).not_to be_empty

          tracker.unregister(with_advisory_lock: true, advisory_lock_connection: other_connection)

          # Lock and record should be unchanged — wrong connection was rejected
          process.reload
          expect(process.lock_type).to eq('advisory')
          expect(tracker).to be_advisory_locked
          expect(PgLock.advisory_lock_details_for(lock_connection)).not_to be_empty
        ensure
          GoodJob::Process.connection_pool.checkin(other_connection)
          tracker.unregister(with_advisory_lock: true, advisory_lock_connection: lock_connection)
          tracker.unregister
        end
      end

      it 'destroys the process record when the original lock connection has been disconnected' do
        other_connection = GoodJob::Process.connection_pool.checkout
        begin
          tracker.register(with_advisory_lock: true, advisory_lock_connection: lock_connection)

          process = GoodJob::Process.last
          expect(process.lock_type).to eq('advisory')

          # Simulate the original connection going inactive (e.g. network drop, server restart).
          # advisory_locked? will return false, so unregister skips the advisory_unlock call —
          # in production the lock is already gone because the connection closed. Here we must
          # release it manually in ensure since the connection is only mocked as inactive.
          allow(lock_connection).to receive(:active?).and_return(false)

          expect(tracker).not_to be_advisory_locked

          # Unregister with a new connection as would happen after reconnect
          tracker.unregister(with_advisory_lock: true, advisory_lock_connection: other_connection)

          expect(GoodJob::Process.count).to eq 0
          expect(tracker.locks).to eq 0
        ensure
          GoodJob::Process.connection_pool.checkin(other_connection)
          # Unstub and release the lock the tracker skipped (simulated disconnect)
          allow(lock_connection).to receive(:active?).and_call_original
          lock_connection.execute("SELECT pg_advisory_unlock_all()")
        end
      end

      context 'with nested registrations' do
        it 'maintains the process when the inner advisory lock dies but the outer non-advisory registration is still active' do
          # register { register(advisory: true) {} }
          tracker.register do
            tracker.register(with_advisory_lock: true, advisory_lock_connection: lock_connection) do
              expect(GoodJob::Process.last.lock_type).to eq('advisory')
              allow(lock_connection).to receive(:active?).and_return(false)
              # inner unregister skips advisory_unlock (dead connection), decrements locks to 1
            end

            # outer registration still holds — process must still exist
            expect(GoodJob::Process.count).to eq 1

            allow(lock_connection).to receive(:active?).and_call_original
            lock_connection.execute("SELECT pg_advisory_unlock_all()")
          end

          expect(GoodJob::Process.count).to eq 0
        end

        it 'maintains the process when the advisory lock dies while an inner non-advisory registration is still active' do
          # register(advisory: true) { register {} }
          # Keep active? mocked through the outer unregister so it doesn't try to advisory_unlock
          # a lock that's already gone. Release manually in ensure afterward.

          tracker.register(with_advisory_lock: true, advisory_lock_connection: lock_connection) do
            allow(lock_connection).to receive(:active?).and_return(false)

            tracker.register do
              expect(GoodJob::Process.count).to eq 1
              # inner unregister detects the dead advisory lock and downgrades lock_type to nil
              # so cleanup on other processes won't incorrectly delete this record
            end

            process = GoodJob::Process.last
            expect(process.lock_type).to be_nil

            # outer advisory registration still holds the registration — process must still exist
            expect(GoodJob::Process.count).to eq 1
            # active? stays mocked so outer unregister sees advisory_locked? = false → record.destroy
          end

          expect(GoodJob::Process.count).to eq 0
        ensure
          allow(lock_connection).to receive(:active?).and_call_original
          lock_connection.execute("SELECT pg_advisory_unlock_all()")
        end
      end
    end

    context 'when NOT used with an advisory lock' do
      it 'does not create a Process' do
        expect do
          tracker.register
        end.not_to change(GoodJob::Process, :count)

        tracker.unregister
      end

      it 'increments the number of locks when not used with a block' do
        expect do
          tracker.register
        end.to change(tracker, :locks).by(1)
        tracker.unregister
      end
    end

    it 'creates a ScheduledTask that refreshes the process in the background' do
      stub_const("GoodJob::Process::STALE_INTERVAL", 0.1.seconds)

      tracker.register do
        tracker.id_for_lock
        updated_at = GoodJob::Process.first.updated_at
        wait_until(max: 1) { expect(GoodJob::Process.first.updated_at).to be > updated_at }
      end

      tracker.register(with_advisory_lock: true) do
        tracker.id_for_lock
        updated_at = GoodJob::Process.first.updated_at
        wait_until(max: 1) { expect(GoodJob::Process.first.updated_at).to be > updated_at }
      end
    end

    it 'resets the number of locks when used with a block' do
      called_block = nil
      tracker.register do
        called_block = true
        expect(tracker.locks).to eq 1
      end

      expect(called_block).to be true
      expect(tracker.locks).to eq 0
    end

    it 'removes the process when locks are zero' do
      inner_block_called = nil
      tracker.register do
        lock_id = tracker.id_for_lock
        expect(lock_id).to be_present

        expect(GoodJob::Process.count).to eq 1
        tracker.register do
          inner_block_called = true
          expect(tracker.id_for_lock).to eq(lock_id)
          expect(GoodJob::Process.count).to eq 1
        end
        expect(GoodJob::Process.count).to eq 1
        expect(tracker.id_for_lock).to eq(lock_id)
      end
      expect(GoodJob::Process.count).to eq 0
      expect(tracker.id_for_lock).to be_nil

      expect(inner_block_called).to be true
    end
  end

  describe '#process_id' do
    it 'is a UUID the process has been locked' do
      expect(tracker.process_id).to be_a_uuid
    end
  end

  describe '.id_for_lock' do
    it 'is available if the process has been registered' do
      expect(GoodJob::Process.count).to eq 0
      expect(tracker.id_for_lock).to be_nil

      tracker.register do
        expect(tracker.id_for_lock).to be_present
      end

      expect(GoodJob::Process.count).to eq 0
      expect(tracker.id_for_lock).to be_nil
    end

    describe "on fork" do
      it 'when reset via ForkTracker' do
        tracker.register do
          original_value = tracker.id_for_lock

          tracker.send(:reset)

          expect(tracker.id_for_lock).not_to eq original_value
        end
      end
    end
  end
end
