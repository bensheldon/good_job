# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::Lockable do
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

      claimed = GoodJob::Job.unfinished.where(locked_by_id: nil).limit(1)
                            .with_skip_locked_claim(locked_by_id: process_id, locked_at: Time.current, lock_type: :skiplocked)

      expect(claimed).to eq job
      expect(claimed.locked_by_id).to eq process_id
      expect(claimed.lock_type).to eq 'skiplocked'
      expect(claimed.locked_at).to be_present
    end

    it 'returns nil when no eligible jobs exist' do
      claimed = GoodJob::Job.unfinished.where(locked_by_id: nil).limit(1)
                            .with_skip_locked_claim(locked_by_id: process_id, locked_at: Time.current, lock_type: :skiplocked)

      expect(claimed).to be_nil
    end

    it 'skips jobs already claimed (locked_by_id is set)' do
      create_job(locked_by_id: SecureRandom.uuid, locked_at: Time.current)

      claimed = GoodJob::Job.unfinished.where(locked_by_id: nil).limit(1)
                            .with_skip_locked_claim(locked_by_id: process_id, locked_at: Time.current, lock_type: :skiplocked)

      expect(claimed).to be_nil
    end

    it 'skips finished jobs' do
      create_job(finished_at: Time.current)

      claimed = GoodJob::Job.unfinished.where(locked_by_id: nil).limit(1)
                            .with_skip_locked_claim(locked_by_id: process_id, locked_at: Time.current, lock_type: :skiplocked)

      expect(claimed).to be_nil
    end

    it 'claims from scoped query respecting WHERE conditions' do
      high_priority_job = create_job(priority: -10)
      _low_priority_job = create_job(priority: 10)

      claimed = GoodJob::Job.unfinished.where(locked_by_id: nil).priority_ordered.limit(1)
                            .with_skip_locked_claim(locked_by_id: process_id, locked_at: Time.current, lock_type: :skiplocked)

      expect(claimed).to eq high_priority_job
    end

    it 'only one concurrent claim succeeds when two threads race for the same job' do
      job = create_job
      barrier = Concurrent::CyclicBarrier.new(2)
      claimant_id_1 = SecureRandom.uuid
      claimant_id_2 = SecureRandom.uuid

      results = [claimant_id_1, claimant_id_2].map do |claimant_id|
        rails_promise do
          barrier.wait
          GoodJob::Job.unfinished.where(locked_by_id: nil).limit(1)
                      .with_skip_locked_claim(locked_by_id: claimant_id, locked_at: Time.current, lock_type: :skiplocked)
        end
      end.map(&:value!)

      claimed = results.compact
      expect(claimed.size).to eq 1
      expect(claimed.first.id).to eq job.id
      expect(GoodJob::Job.where(id: job.id).pick(:locked_by_id)).to be_in([claimant_id_1, claimant_id_2])
    end
  end

  describe '.with_hybrid_lock_claim' do
    it 'claims the first available job, sets lock columns, and acquires a session advisory lock' do
      job = create_job

      GoodJob::Job.lease_connection # sticky connection required for advisory lock
      claimed = GoodJob::Job.unfinished.where(locked_by_id: nil).limit(1)
                            .with_hybrid_lock_claim(locked_by_id: process_id, locked_at: Time.current, lock_type: :hybrid)

      expect(claimed).to eq job
      expect(claimed.locked_by_id).to eq process_id
      expect(claimed.lock_type).to eq 'hybrid'
      expect(claimed.locked_at).to be_present
      expect(PgLock.current_database.advisory_lock.owns.count).to eq 1

      claimed.advisory_unlock
    end

    it 'returns nil when no eligible jobs exist' do
      GoodJob::Job.lease_connection
      claimed = GoodJob::Job.unfinished.where(locked_by_id: nil).limit(1)
                            .with_hybrid_lock_claim(locked_by_id: process_id, locked_at: Time.current, lock_type: :hybrid)

      expect(claimed).to be_nil
    end

    it 'skips jobs already claimed (locked_by_id is set)' do
      create_job(locked_by_id: SecureRandom.uuid, locked_at: Time.current)

      GoodJob::Job.lease_connection
      claimed = GoodJob::Job.unfinished.where(locked_by_id: nil).limit(1)
                            .with_hybrid_lock_claim(locked_by_id: process_id, locked_at: Time.current, lock_type: :hybrid)

      expect(claimed).to be_nil
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
          result = GoodJob::Job.unfinished.where(locked_by_id: nil).limit(1)
                               .with_hybrid_lock_claim(locked_by_id: claimant_id, locked_at: Time.current, lock_type: :hybrid)
          result&.advisory_unlock
          result
        end
      end.map(&:value!)

      claimed = results.compact
      expect(claimed.size).to eq 1
      expect(claimed.first.id).to eq job.id
    end
  end
end
