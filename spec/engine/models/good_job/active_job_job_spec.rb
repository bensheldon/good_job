# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::ActiveJobJob do
  subject(:job) { described_class.find(head_execution.active_job_id) }

  let!(:tail_execution) do
    GoodJob::Execution.create!(
      active_job_id: SecureRandom.uuid,
      created_at: 1.minute.ago,
      queue_name: 'mice',
      serialized_params: {
        'job_class' => 'TestJob',
        'executions' => 0,
      }
    )
  end

  let!(:head_execution) do
    GoodJob::Execution.create!(
      active_job_id: tail_execution.active_job_id,
      queue_name: 'mice',
      serialized_params: {
        'job_class' => 'TestJob',
        'executions' => 1,
      }
    ).tap do |execution|
      tail_execution.update!(
        retried_good_job_id: execution.id,
        error: "TestJob::Error: TestJob::Error",
        finished_at: execution.created_at
      )
    end
  end

  describe '.find' do
    it 'returns a record that is the same as the head execution' do
      job = described_class.find(head_execution.active_job_id)
      expect(job.executions.last).to eq head_execution
    end
  end

  describe '#id' do
    it 'is the ActiveJob ID' do
      expect(job.id).to eq head_execution.active_job_id
    end
  end

  describe '#job_class' do
    it 'is the job class' do
      expect(job.id).to eq head_execution.active_job_id
    end
  end

  describe '#head_execution' do
    it 'is the head execution (which should be the same record)' do
      expect(job.head_execution).to eq head_execution
      expect(job._execution_id).to eq head_execution.id
    end
  end

  describe '#tail_execution' do
    it 'is the tail execution' do
      expect(job.tail_execution).to eq tail_execution
    end
  end

  describe '#recent_error' do
    it 'is the current executions error or the previous jobs error' do
      expect(job.recent_error).to eq tail_execution.error
    end
  end

  describe '#running?' do
    context 'when advisory_locks are NOT eagerloaded' do
      it 'is true if the job is Advisory Locked' do
        job.with_advisory_lock do
          expect(job).to be_running
        end
      end
    end

    context 'when advisory_locks are eagerloaded' do
      it 'is true if the job is Advisory Locked' do
        job.with_advisory_lock do
          eagerloaded_job = described_class.where(active_job_id: job.id).joins_advisory_locks.select('good_jobs.*', 'pg_locks.locktype AS locktype').first
          expect(eagerloaded_job).to be_running
        end
      end
    end

    it 'is true if the job is Advisory Locked' do
      job.with_advisory_lock do
        job_with_locktype = described_class.where(active_job_id: job.id).joins_advisory_locks.select('good_jobs.*', 'pg_locks.locktype AS locktype').first
        expect(job_with_locktype).to be_running
      end
    end
  end
end
