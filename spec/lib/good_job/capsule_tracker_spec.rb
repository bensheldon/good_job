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

        Rails.logger.warn("DONE WITH TEST")
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
    it 'is a UUID' do
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
        skip("AS::ForkTracker is not defined") unless defined?(ActiveSupport::ForkTracker)

        tracker.register do
          original_value = tracker.id_for_lock

          tracker.send(:reset)

          expect(tracker.id_for_lock).not_to eq original_value
        end
      end
    end
  end
end
