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
      it 'releases persisted claims after completion attributes were cleared only in memory' do
        job = create_job
        failure = ActiveRecord::ConnectionNotEstablished.new('completion failed')
        GoodJob::ConcurrencyClaim.create!(key: 'cleanup-test', job_id: job.id, locked_by_id: process_id, state: GoodJob::ConcurrencyClaim::GRANTED)

        expect do
          GoodJob::Job.where(id: job.id).public_send("with_#{strategy == :skiplocked ? 'skip_locked' : 'hybrid_lock'}_claim", locked_by_id: process_id, locked_at: Time.current, lock_type: strategy) do |record|
            record.assign_attributes(locked_by_id: nil, locked_at: nil, lock_type: nil, finished_at: Time.current)
            raise failure
          end
        end.to raise_error(failure)

        expect(job.reload).to have_attributes(finished_at: nil, locked_by_id: nil, locked_at: nil, lock_type: nil)
        expect(GoodJob::ConcurrencyClaim.where(job_id: job.id)).to be_empty
      end

      it 'does not release a claim acquired later by the same process' do
        job = create_job
        locked_at = Time.current
        next_locked_at = locked_at + 1.second
        claim = GoodJob::ConcurrencyClaim.create!(key: 'cleanup-test', job_id: job.id, locked_by_id: process_id, state: GoodJob::ConcurrencyClaim::GRANTED)

        GoodJob::Job.where(id: job.id).public_send("with_#{strategy == :skiplocked ? 'skip_locked' : 'hybrid_lock'}_claim", locked_by_id: process_id, locked_at: locked_at, lock_type: strategy) do |record|
          GoodJob::Job.find(job.id).update!(locked_at: next_locked_at)
          record.assign_attributes(locked_by_id: nil, locked_at: nil, finished_at: Time.current)
        end

        expect(job.reload).to have_attributes(locked_by_id: process_id, locked_at: within(0.001).of(next_locked_at), finished_at: nil)
        expect(claim.reload.state).to eq GoodJob::ConcurrencyClaim::GRANTED
      end

      it 'does not release another process claim after a failure' do
        job = create_job
        next_process_id = SecureRandom.uuid
        failure = StandardError.new('failed after ownership changed')
        claim = GoodJob::ConcurrencyClaim.create!(key: 'cleanup-test', job_id: job.id, locked_by_id: next_process_id, state: GoodJob::ConcurrencyClaim::GRANTED)

        expect do
          GoodJob::Job.where(id: job.id).public_send("with_#{strategy == :skiplocked ? 'skip_locked' : 'hybrid_lock'}_claim", locked_by_id: process_id, locked_at: Time.current, lock_type: strategy) do |record|
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
