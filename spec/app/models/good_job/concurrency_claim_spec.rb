# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::ConcurrencyClaim do
  let(:key) { "label:testlabel" }

  def create_job(performed_at: nil, finished_at: nil, scheduled_at: 1.hour.from_now)
    GoodJob::Job.create!(
      active_job_id: SecureRandom.uuid,
      queue_name: "default",
      job_class: "TestJob",
      serialized_params: {},
      performed_at: performed_at,
      finished_at: finished_at,
      scheduled_at: scheduled_at
    )
  end

  describe '.claim' do
    it 'grants up to the limit and records the rest as waiting' do
      job_a = create_job(performed_at: Time.current)
      job_b = create_job

      expect(described_class.claim(key: key, scope: GoodJob::Job.all, limit: 1, job_id: job_a.id, locked_by_id: nil)).to be true
      job_b.update!(performed_at: Time.current)
      expect(described_class.claim(key: key, scope: GoodJob::Job.all, limit: 1, job_id: job_b.id, locked_by_id: nil)).to be false

      expect(described_class.where(job_id: job_b.id).pluck(:state)).to eq [described_class::WAITING]
    end

    it 'reuses its own existing grant and updates locked_by_id' do
      job = create_job(performed_at: Time.current)
      process_id = SecureRandom.uuid
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 1, job_id: job.id, locked_by_id: nil)

      expect(described_class.claim(key: key, scope: GoodJob::Job.all, limit: 1, job_id: job.id, locked_by_id: process_id)).to be true
      expect(described_class.where(job_id: job.id).pluck(:locked_by_id)).to eq [process_id]
    end

    it 'keeps only the waiting claim for the latest key' do
      job = create_job
      described_class.claim(key: "label:first", scope: GoodJob::Job.all, limit: 0, job_id: job.id, locked_by_id: nil)
      described_class.claim(key: "label:second", scope: GoodJob::Job.all, limit: 0, job_id: job.id, locked_by_id: nil)

      expect(described_class.where(job_id: job.id).pluck(:key, :state)).to eq [["label:second", described_class::WAITING]]
    end
  end

  describe '.release_job' do
    it 'touches updated_at while preserving created_at when promoting' do
      holder = create_job(performed_at: Time.current)
      waiter = create_job
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 1, job_id: holder.id, locked_by_id: nil)
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 1, job_id: waiter.id, locked_by_id: nil)
      created_at = described_class.find_by(job_id: waiter.id).created_at

      holder.update!(finished_at: Time.current)
      Timecop.travel(1.minute) { described_class.release_job(holder.id) }

      promoted_claim = described_class.find_by(job_id: waiter.id)
      expect(promoted_claim.state).to eq described_class::PROMOTED
      expect(promoted_claim.created_at).to eq created_at
      expect(promoted_claim.updated_at).to be > created_at + 30.seconds
    end

    it 'deletes grants and makes the oldest waiting job runnable' do
      holder = create_job(performed_at: Time.current)
      first_waiter = create_job
      second_waiter = create_job
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 1, job_id: holder.id, locked_by_id: nil)
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 0, job_id: first_waiter.id, locked_by_id: nil)
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 0, job_id: second_waiter.id, locked_by_id: nil)

      allow(GoodJob::Notifier).to receive(:notify)
      described_class.release_job(holder.id)

      expect(described_class.where(job_id: holder.id)).to be_empty
      expect(first_waiter.reload.scheduled_at).to be <= Time.current
      expect(second_waiter.reload.scheduled_at).to be > Time.current
      expect(GoodJob::Notifier).to have_received(:notify).with({ queue_name: "default" })
    end

    it 'skips and deletes waiting rows for jobs that are finished or missing' do
      holder = create_job(performed_at: Time.current)
      finished_waiter = create_job(finished_at: Time.current)
      waiter = create_job
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 1, job_id: holder.id, locked_by_id: nil)
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 0, job_id: finished_waiter.id, locked_by_id: nil)
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 0, job_id: SecureRandom.uuid, locked_by_id: nil)
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 0, job_id: waiter.id, locked_by_id: nil)

      described_class.release_job(holder.id)

      expect(waiter.reload.scheduled_at).to be <= Time.current
      expect(described_class.pluck(:job_id)).to eq [waiter.id]
    end

    it 'marks a waiter that is still finishing its rejected execution, which runs once rescheduled' do
      holder = create_job(performed_at: Time.current)
      waiter = create_job
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 1, job_id: holder.id, locked_by_id: nil)
      waiter.update!(performed_at: Time.current)
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 0, job_id: waiter.id, locked_by_id: nil)

      described_class.release_job(holder.id)
      expect(described_class.find_by(job_id: waiter.id).state).to eq described_class::PROMOTION_PENDING

      # The waiter's retry reschedules it
      waiter.update!(performed_at: nil, scheduled_at: 1.hour.from_now)
      described_class.job_finished(waiter)

      expect(waiter.reload.scheduled_at).to be <= Time.current
      expect(described_class.find_by(job_id: waiter.id).state).to eq described_class::PROMOTED
    end
  end

  describe 'multiple slot releases' do
    [nil, :running, :rescheduled].each do |waiter_state|
      it "promotes distinct waiters when the first waiter is #{waiter_state || 'queued'}" do
        holders = Array.new(2) { create_job(performed_at: Time.current) }
        first_waiter = create_job
        second_waiter = create_job
        holders.each do |holder|
          described_class.claim(key: key, scope: GoodJob::Job.all, limit: 2, job_id: holder.id, locked_by_id: nil)
        end
        first_waiter.update!(performed_at: Time.current) if waiter_state
        [first_waiter, second_waiter].each do |waiter|
          described_class.claim(key: key, scope: GoodJob::Job.all, limit: 0, job_id: waiter.id, locked_by_id: nil)
        end

        described_class.release_job(holders.first.id)
        if waiter_state == :rescheduled
          first_waiter.update!(performed_at: nil)
          described_class.job_finished(first_waiter)
        end
        described_class.release_job(holders.last.id)

        expect(second_waiter.reload.scheduled_at).to be <= Time.current
        if waiter_state == :running
          expect(described_class.find_by(job_id: first_waiter.id).state).to eq described_class::PROMOTION_PENDING
          first_waiter.update!(performed_at: nil)
          described_class.job_finished(first_waiter)
        end
        expect(first_waiter.reload.scheduled_at).to be <= Time.current
        expect(described_class.where(job_id: [first_waiter.id, second_waiter.id]).pluck(:state)).to eq [described_class::PROMOTED, described_class::PROMOTED]
      end
    end

    it 'promotes a waiter for each grant released by a process' do
      process_id = SecureRandom.uuid
      holders = Array.new(2) { create_job(performed_at: Time.current) }
      waiters = Array.new(2) { create_job }
      holders.each do |holder|
        described_class.claim(key: key, scope: GoodJob::Job.all, limit: 2, job_id: holder.id, locked_by_id: process_id)
      end
      waiters.each do |waiter|
        described_class.claim(key: key, scope: GoodJob::Job.all, limit: 0, job_id: waiter.id, locked_by_id: nil)
      end

      described_class.release_process(process_id)

      expect(waiters.map { |waiter| waiter.reload.scheduled_at }).to all(be <= Time.current)
    end

    it 'rechecks the limit when a promoted job retries' do
      holder = create_job(performed_at: Time.current)
      waiter = create_job
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 1, job_id: holder.id, locked_by_id: nil)
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 0, job_id: waiter.id, locked_by_id: nil)
      described_class.release_job(holder.id)

      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 1, job_id: holder.id, locked_by_id: nil)
      expect(described_class.claim(key: key, scope: GoodJob::Job.all, limit: 1, job_id: waiter.id, locked_by_id: nil)).to be false
      expect(described_class.find_by(job_id: waiter.id).state).to eq described_class::WAITING

      holder.update!(finished_at: Time.current)
      described_class.release_job(holder.id)
      expect(described_class.claim(key: key, scope: GoodJob::Job.all, limit: 1, job_id: waiter.id, locked_by_id: nil)).to be true
      expect(described_class.find_by(job_id: waiter.id).state).to eq described_class::GRANTED
    end

    it 'promotes the next waiter on a second release rather than the already-promoted one' do
      holders = Array.new(2) { create_job(performed_at: Time.current) }
      first_waiter = create_job
      second_waiter = create_job
      holders.each { |holder| described_class.claim(key: key, scope: GoodJob::Job.all, limit: 2, job_id: holder.id, locked_by_id: nil) }
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 2, job_id: first_waiter.id, locked_by_id: nil)
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 2, job_id: second_waiter.id, locked_by_id: nil)

      described_class.release_job(holders.first.id)
      expect(described_class.find_by(job_id: first_waiter.id).state).to eq described_class::PROMOTED
      expect(second_waiter.reload.scheduled_at).to be > Time.current

      described_class.release_job(holders.last.id)
      expect(second_waiter.reload.scheduled_at).to be <= Time.current
    end

    it 'returns a promoted job that is rejected again to waiting, keeping its position' do
      holder = create_job(performed_at: Time.current)
      first_waiter = create_job
      second_waiter = create_job
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 1, job_id: holder.id, locked_by_id: nil)
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 1, job_id: first_waiter.id, locked_by_id: nil)
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 1, job_id: second_waiter.id, locked_by_id: nil)
      first_created_at = described_class.find_by(job_id: first_waiter.id).created_at

      holder.update!(finished_at: Time.current)
      described_class.release_job(holder.id)

      # Another job takes the slot before the promoted job runs
      other = create_job(performed_at: Time.current)
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 1, job_id: other.id, locked_by_id: nil)
      first_waiter.update!(performed_at: Time.current)
      expect(described_class.claim(key: key, scope: GoodJob::Job.all, limit: 1, job_id: first_waiter.id, locked_by_id: nil)).to be false

      first_claim = described_class.find_by(job_id: first_waiter.id)
      expect(first_claim.state).to eq described_class::WAITING
      expect(first_claim.created_at).to eq first_created_at
      expect(described_class.waiting.where(key: key).order(:created_at).pluck(:job_id)).to eq [first_waiter.id, second_waiter.id]
    end
  end

  describe '.release_process' do
    it 'releases grants held by the process and promotes waiters' do
      process_id = SecureRandom.uuid
      holder = create_job(performed_at: Time.current)
      waiter = create_job
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 1, job_id: holder.id, locked_by_id: process_id)
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 0, job_id: waiter.id, locked_by_id: nil)

      described_class.release_process(process_id)

      expect(described_class.granted).to be_empty
      expect(waiter.reload.scheduled_at).to be <= Time.current
    end

    it 'promotes a waiter for each grant released on the same key' do
      process_id = SecureRandom.uuid
      holders = Array.new(2) { create_job(performed_at: Time.current) }
      waiters = Array.new(2) { create_job }
      holders.each { |holder| described_class.claim(key: key, scope: GoodJob::Job.all, limit: 2, job_id: holder.id, locked_by_id: process_id) }
      waiters.each { |waiter| described_class.claim(key: key, scope: GoodJob::Job.all, limit: 2, job_id: waiter.id, locked_by_id: nil) }

      described_class.release_process(process_id)

      expect(waiters.map { |waiter| waiter.reload.scheduled_at }).to all(be <= Time.current)
    end
  end

  describe '.job_finished' do
    it 'sees a pending promotion committed by a concurrent promoter' do
      waiter = create_job(performed_at: Time.current)
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 0, job_id: waiter.id, locked_by_id: nil)
      waiter.update!(performed_at: nil, scheduled_at: 1.hour.from_now)

      locked = Concurrent::Event.new
      commit = Concurrent::Event.new
      promoter = Thread.new do
        described_class.connection_pool.with_connection do
          described_class.transaction do
            claim = described_class.where(job_id: waiter.id).lock.first
            claim.update_columns(state: described_class::PROMOTION_PENDING) # rubocop:disable Rails/SkipsModelValidations
            locked.set
            commit.wait(5)
          end
        end
      end
      locked.wait(5)

      finisher = Thread.new do
        described_class.connection_pool.with_connection { described_class.job_finished(waiter) }
      end
      sleep 0.2
      commit.set
      promoter.join(5)
      finisher.join(5)

      expect(waiter.reload.scheduled_at).to be <= Time.current
      expect(described_class.find_by(job_id: waiter.id).state).to eq described_class::PROMOTED
    end

    it 'deletes all rows of a finished job' do
      job = create_job
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 0, job_id: job.id, locked_by_id: nil)
      job.update!(finished_at: Time.current)

      described_class.job_finished(job)

      expect(described_class.count).to eq 0
    end
  end

  describe '.cleanup_orphaned' do
    it 'deletes rows whose job is missing or finished' do
      unfinished = create_job
      finished = create_job(finished_at: Time.current)
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 0, job_id: unfinished.id, locked_by_id: nil)
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 0, job_id: finished.id, locked_by_id: nil)
      described_class.claim(key: key, scope: GoodJob::Job.all, limit: 0, job_id: SecureRandom.uuid, locked_by_id: nil)

      expect(described_class.cleanup_orphaned).to eq 2
      expect(described_class.pluck(:job_id)).to eq [unfinished.id]
    end
  end
end
