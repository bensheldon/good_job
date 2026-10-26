# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::Job::Lockable do
  let(:process_id) { SecureRandom.uuid }

  around do |example|
    Rails.application.executor.wrap { example.run }
  end

  before do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
  end

  def create_job(attrs = {})
    GoodJob::Job.create!(
      {
        active_job_id: SecureRandom.uuid,
        queue_name: 'default',
        priority: 0,
        job_class: 'TestJob',
        scheduled_at: 1.minute.ago,
        serialized_params: { 'job_class' => 'TestJob', 'job_id' => SecureRandom.uuid, 'queue_name' => 'default', 'arguments' => [] },
      }.merge(attrs)
    )
  end

  describe '.with_advisory_lock_claim' do
    it 'runs perform_unlocked callbacks after the advisory lock is released' do
      job = create_job
      locked_during_callback = nil
      allow_any_instance_of(GoodJob::Job).to receive(:continue_discard_or_finish_batch) do |record|
        locked_during_callback = record.advisory_locked?
      end

      GoodJob::Job.where(id: job.id).with_advisory_lock_claim { |claimed| expect(claimed).to be_advisory_locked }

      expect(locked_during_callback).to be false
    end

    it 'runs perform_unlocked callbacks when the block raises after the row lock is released' do
      job = create_job
      callback_ran = false
      allow_any_instance_of(GoodJob::Job).to receive(:continue_discard_or_finish_batch) { callback_ran = true }

      expect do
        GoodJob::Job.where(id: job.id).with_advisory_lock_claim { raise 'boom' }
      end.to raise_error('boom')

      expect(callback_ran).to be true
    end

    it 'skips perform_unlocked callbacks when the row lock was not released' do
      job = create_job(locked_by_id: process_id, locked_at: Time.current, lock_type: :advisory)
      callback_ran = false
      allow_any_instance_of(GoodJob::Job).to receive(:continue_discard_or_finish_batch) { callback_ran = true }

      expect do
        GoodJob::Job.where(id: job.id).with_advisory_lock_claim { raise 'completion failed' }
      end.to raise_error('completion failed')

      expect(callback_ran).to be false
    end
  end

  describe '.with_skip_locked_claim' do
    it 'claims the first available job and sets lock columns' do
      job = create_job

      GoodJob::Job.unfinished.where(locked_by_id: nil).limit(1)
                  .with_skip_locked_claim(locked_by_id: process_id, locked_at: Time.current, lock_type: :skiplocked) do |claimed|
        expect(claimed).to eq job
        expect(claimed.locked_by_id).to eq process_id
        expect(claimed.lock_type).to eq 'skiplocked'
        expect(claimed.locked_at).to be_present
      end
    end

    it 'yields nil when no eligible jobs exist' do
      GoodJob::Job.unfinished.where(locked_by_id: nil).limit(1)
                  .with_skip_locked_claim(locked_by_id: process_id, locked_at: Time.current, lock_type: :skiplocked) do |claimed|
        expect(claimed).to be_nil
      end
    end

    it 'skips jobs already claimed (locked_by_id is set)' do
      create_job(locked_by_id: SecureRandom.uuid, locked_at: Time.current)

      GoodJob::Job.unfinished.where(locked_by_id: nil).limit(1)
                  .with_skip_locked_claim(locked_by_id: process_id, locked_at: Time.current, lock_type: :skiplocked) do |claimed|
        expect(claimed).to be_nil
      end
    end

    it 'skips finished jobs' do
      create_job(finished_at: Time.current)

      GoodJob::Job.unfinished.where(locked_by_id: nil).limit(1)
                  .with_skip_locked_claim(locked_by_id: process_id, locked_at: Time.current, lock_type: :skiplocked) do |claimed|
        expect(claimed).to be_nil
      end
    end

    it 'claims from scoped query respecting WHERE conditions' do
      high_priority_job = create_job(priority: -10)
      _low_priority_job = create_job(priority: 10)

      GoodJob::Job.unfinished.where(locked_by_id: nil).priority_ordered.limit(1)
                  .with_skip_locked_claim(locked_by_id: process_id, locked_at: Time.current, lock_type: :skiplocked) do |claimed|
        expect(claimed).to eq high_priority_job
      end
    end

    it 'only one concurrent claim succeeds when two threads race for the same job' do
      job = create_job
      start_barrier = Concurrent::CyclicBarrier.new(2)
      claimed_event = Concurrent::CountDownLatch.new(2)

      results = Concurrent::Array.new

      promises = Array.new(2) do |_i|
        rails_promise do
          start_barrier.wait
          GoodJob::Job.unfinished.where(locked_by_id: nil).limit(1)
                      .with_skip_locked_claim(locked_by_id: SecureRandom.uuid, locked_at: Time.current, lock_type: :skiplocked) do |record|
            results << record
            claimed_event.count_down
            claimed_event.wait(5)
          end
        end
      end
      promises.each(&:value!)

      expect(results.compact.size).to eq 1
      expect(results.compact.first.id).to eq job.id
    end
  end

  describe '.with_hybrid_lock_claim' do
    it 'releases the row claim even if advisory unlock raises' do
      job = create_job

      expect do
        GoodJob::Job.where(id: job.id).with_hybrid_lock_claim(locked_by_id: process_id, locked_at: Time.current, lock_type: :hybrid) do |claimed|
          allow(claimed).to receive(:advisory_unlock).and_wrap_original do |method, **kwargs|
            method.call(**kwargs)
            raise ActiveRecord::ConnectionNotEstablished, 'unlock response lost'
          end
        end
      end.to raise_error(ActiveRecord::ConnectionNotEstablished, 'unlock response lost')

      expect(job.reload).to have_attributes(locked_by_id: nil, locked_at: nil, lock_type: nil)
    end

    it 'uses the configured advisory lock hash for claiming and releasing' do
      allow(GoodJob::AdvisoryLockable).to receive(:hash_function).and_return('hashtext')
      job = create_job

      GoodJob::Job.where(id: job.id).with_hybrid_lock_claim(locked_by_id: process_id, locked_at: Time.current, lock_type: :hybrid) do |claimed|
        expect(claimed.owns_advisory_lock?).to be true
      end

      expect(PgLock.current_database.advisory_lock.owns.count).to eq 0
    end

    it 'claims the first available job, sets lock columns, and acquires a session advisory lock' do
      job = create_job

      GoodJob::Job.unfinished.where(locked_by_id: nil).limit(1)
                  .with_hybrid_lock_claim(locked_by_id: process_id, locked_at: Time.current, lock_type: :hybrid) do |claimed|
        expect(claimed).to eq job
        expect(claimed.locked_by_id).to eq process_id
        expect(claimed.lock_type).to eq 'hybrid'
        expect(claimed.locked_at).to be_present
        expect(PgLock.current_database.advisory_lock.owns.count).to eq 1
      end
    end

    it 'yields nil when no eligible jobs exist' do
      GoodJob::Job.unfinished.where(locked_by_id: nil).limit(1)
                  .with_hybrid_lock_claim(locked_by_id: process_id, locked_at: Time.current, lock_type: :hybrid) do |claimed|
        expect(claimed).to be_nil
      end
    end

    it 'skips jobs already claimed (locked_by_id is set)' do
      create_job(locked_by_id: SecureRandom.uuid, locked_at: Time.current)

      GoodJob::Job.unfinished.where(locked_by_id: nil).limit(1)
                  .with_hybrid_lock_claim(locked_by_id: process_id, locked_at: Time.current, lock_type: :hybrid) do |claimed|
        expect(claimed).to be_nil
      end
    end

    it 'only one concurrent claim succeeds when two threads race for the same job' do
      job = create_job
      barrier = Concurrent::CyclicBarrier.new(2)
      claimant_id_1 = SecureRandom.uuid
      claimant_id_2 = SecureRandom.uuid

      results = [claimant_id_1, claimant_id_2].map do |claimant_id|
        rails_promise do
          GoodJob::Job.lease_connection
          barrier.wait
          claimed = nil
          GoodJob::Job.unfinished.where(locked_by_id: nil).limit(1)
                      .with_hybrid_lock_claim(locked_by_id: claimant_id, locked_at: Time.current, lock_type: :hybrid) do |record|
            claimed = record
          end
          claimed
        end
      end.map(&:value!)

      claimed = results.compact
      expect(claimed.size).to eq 1
      expect(claimed.first.id).to eq job.id
    end
  end

  [:skiplocked, :hybrid].each do |strategy|
    describe "#{strategy} claim cleanup" do
      let(:claim_method) { strategy == :skiplocked ? :with_skip_locked_claim : :with_hybrid_lock_claim }

      it 'releases persisted claims after completion attributes were cleared only in memory' do
        job = create_job
        failure = ActiveRecord::ConnectionNotEstablished.new('completion failed')
        GoodJob::ConcurrencyClaim.create!(key: 'cleanup-test', job_id: job.id, locked_by_id: process_id, state: GoodJob::ConcurrencyClaim::GRANTED)

        expect do
          GoodJob::Job.where(id: job.id).public_send(claim_method, locked_by_id: process_id, locked_at: Time.current, lock_type: strategy) do |record|
            record.assign_attributes(locked_by_id: nil, locked_at: nil, lock_type: nil, finished_at: Time.current)
            raise failure
          end
        end.to raise_error(failure)

        expect(job.reload).to have_attributes(finished_at: nil, locked_by_id: nil, locked_at: nil, lock_type: nil)
        expect(GoodJob::ConcurrencyClaim.where(job_id: job.id)).to be_empty
      end

      it 'retries connection failures until the original claim can be released' do
        job = create_job
        failure = ActiveRecord::ConnectionNotEstablished.new('still disconnected')
        attempts = 0
        allow(GoodJob::Job).to receive(:sleep)
        allow(GoodJob.logger).to receive(:warn)

        expect do
          GoodJob::Job.where(id: job.id).public_send(claim_method, locked_by_id: process_id, locked_at: Time.current, lock_type: strategy) do
            allow(GoodJob::Job).to receive(:transaction).and_wrap_original do |method, *args, **kwargs, &block|
              attempts += 1
              raise failure if attempts <= 4

              method.call(*args, **kwargs, &block)
            end
            raise 'completion failed'
          end
        end.to raise_error('completion failed')

        expect(attempts).to eq 5
        expect(GoodJob::Job).to have_received(:sleep).with(5).exactly(4).times
        expect(GoodJob.logger).to have_received(:warn).with(/could not release the claim on job #{job.id} \(attempt 1\)/).once
        expect(job.reload).to have_attributes(locked_by_id: nil, locked_at: nil, lock_type: nil)
      end

      it 'releases the row lock and concurrency grant in the same transaction' do
        job = create_job
        claim = GoodJob::ConcurrencyClaim.create!(key: 'cleanup-test', job_id: job.id, locked_by_id: process_id, state: GoodJob::ConcurrencyClaim::GRANTED)
        attempts = 0
        allow(GoodJob::ConcurrencyClaim).to receive(:release_job).and_wrap_original do |method, *args|
          method.call(*args)
          attempts += 1
          raise ActiveRecord::ConnectionNotEstablished, 'lost connection' if attempts == 1
        end
        allow(GoodJob::Job).to receive(:sleep) do
          expect(job.reload.locked_by_id).to eq process_id
          expect(claim.reload.state).to eq GoodJob::ConcurrencyClaim::GRANTED
        end

        result = GoodJob::Job.where(id: job.id).public_send(claim_method, locked_by_id: process_id, locked_at: Time.current, lock_type: strategy) { :block_result }

        expect(result).to eq :block_result
        expect(attempts).to eq 2
        expect(job.reload.locked_by_id).to be_nil
        expect(GoodJob::ConcurrencyClaim.where(job_id: job.id)).to be_empty
      end

      it 'stops retrying when the worker is shutting down' do
        job = create_job
        allow(GoodJob::Job).to receive(:transaction).and_raise(ActiveRecord::ConnectionNotEstablished, 'database unavailable')
        allow(GoodJob::Job).to receive(:sleep)
        allow(GoodJob).to receive(:current_thread_shutting_down?).and_return(true)

        expect do
          GoodJob::Job.where(id: job.id).public_send(claim_method, locked_by_id: process_id, locked_at: Time.current, lock_type: strategy) do
            raise 'completion failed'
          end
        end.to raise_error('completion failed')

        expect(GoodJob::Job).not_to have_received(:sleep)
      end

      it 'does not keep a killed worker alive while the database is unavailable' do
        job = create_job
        allow(GoodJob::Job).to receive(:transaction).and_raise(ActiveRecord::ConnectionNotEstablished, 'database unavailable')
        allow(GoodJob::Job).to receive(:sleep)

        ActiveSupport::Dependencies.interlock.permit_concurrent_loads do
          thread = Thread.new do
            Rails.application.executor.wrap do
              GoodJob::Job.where(id: job.id).public_send(claim_method, locked_by_id: process_id, locked_at: Time.current, lock_type: strategy) do
                Thread.current.kill
              end
            end
          end
          expect(thread.join(2)).to eq thread
        ensure
          # Also let a regressed implementation finish, rather than leaking its thread.
          allow(GoodJob::Job).to receive(:transaction).and_call_original
          thread&.join(5)
        end
      end

      it 'does not retry unrelated cleanup errors' do
        job = create_job
        allow(GoodJob::Job).to receive(:sleep)

        expect do
          GoodJob::Job.where(id: job.id).public_send(claim_method, locked_by_id: process_id, locked_at: Time.current, lock_type: strategy) do
            allow(GoodJob::Job).to receive(:transaction).and_raise(ActiveRecord::StatementInvalid, 'bad SQL')
          end
        end.to raise_error(ActiveRecord::StatementInvalid, 'bad SQL')

        expect(GoodJob::Job).not_to have_received(:sleep)
      end

      it 'does not mistake a cleanup error caused by an earlier disconnect for a connection error' do
        job = create_job
        attempts = 0
        allow(GoodJob::Job).to receive(:sleep)

        expect do
          GoodJob::Job.where(id: job.id).public_send(claim_method, locked_by_id: process_id, locked_at: Time.current, lock_type: strategy) do
            allow(GoodJob::Job).to receive(:transaction).and_wrap_original do |method, *args, **kwargs, &block|
              attempts += 1
              raise ArgumentError, 'unrelated cleanup error' if attempts == 1

              method.call(*args, **kwargs, &block)
            end
            raise ActiveRecord::ConnectionNotEstablished, 'completion disconnected'
          end
        end.to raise_error(ArgumentError, 'unrelated cleanup error')

        expect(GoodJob::Job).not_to have_received(:sleep)
      end

      it 'recognizes wrapped PostgreSQL connection errors', skip: RUBY_PLATFORM.include?('java') do
        job = create_job
        attempts = 0
        allow(GoodJob::Job).to receive(:sleep)

        GoodJob::Job.where(id: job.id).public_send(claim_method, locked_by_id: process_id, locked_at: Time.current, lock_type: strategy) do
          allow(GoodJob::Job).to receive(:transaction).and_wrap_original do |method, *args, **kwargs, &block|
            attempts += 1
            if attempts == 1
              begin
                raise PG::ConnectionBad, 'connection lost'
              rescue PG::ConnectionBad
                raise ActiveRecord::StatementInvalid, 'could not release claim'
              end
            end
            method.call(*args, **kwargs, &block)
          end
        end

        expect(GoodJob::Job).to have_received(:sleep).with(5).once
        expect(job.reload.locked_by_id).to be_nil
      end

      it 'does not release a claim acquired later by the same process' do
        batch = GoodJob::BatchRecord.create!(enqueued_at: Time.current)
        job = create_job(batch_id: batch.id)
        locked_at = Time.current
        next_locked_at = locked_at + 1.second
        claim = GoodJob::ConcurrencyClaim.create!(key: 'cleanup-test', job_id: job.id, locked_by_id: process_id, state: GoodJob::ConcurrencyClaim::GRANTED)

        GoodJob::Job.where(id: job.id).public_send(claim_method, locked_by_id: process_id, locked_at: locked_at, lock_type: strategy) do |record|
          GoodJob::Job.find(job.id).update!(locked_at: next_locked_at)
          record.assign_attributes(locked_by_id: nil, locked_at: nil, finished_at: Time.current, error: 'uncommitted error')
        end

        expect(job.reload).to have_attributes(locked_by_id: process_id, locked_at: within(0.001).of(next_locked_at), finished_at: nil)
        expect(claim.reload.state).to eq GoodJob::ConcurrencyClaim::GRANTED
        expect(batch.reload.discarded_at).to be_nil
      end

      it 'does not release another process claim after a failure' do
        job = create_job
        next_process_id = SecureRandom.uuid
        failure = StandardError.new('failed after ownership changed')
        claim = GoodJob::ConcurrencyClaim.create!(key: 'cleanup-test', job_id: job.id, locked_by_id: next_process_id, state: GoodJob::ConcurrencyClaim::GRANTED)

        expect do
          GoodJob::Job.where(id: job.id).public_send(claim_method, locked_by_id: process_id, locked_at: Time.current, lock_type: strategy) do |record|
            GoodJob::Job.find(job.id).update!(locked_by_id: next_process_id)
            record.assign_attributes(locked_by_id: nil, finished_at: Time.current)
            raise failure
          end
        end.to raise_error(failure)

        expect(job.reload).to have_attributes(locked_by_id: next_process_id, finished_at: nil)
        expect(claim.reload.state).to eq GoodJob::ConcurrencyClaim::GRANTED
      end
    end
  end
end
