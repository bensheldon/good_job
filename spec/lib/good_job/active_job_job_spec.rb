# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::ActiveJobJob do
  subject(:job) { described_class.find(head_execution.active_job_id) }

  before do
    allow(GoodJob).to receive(:preserve_job_records).and_return(true)
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)

    stub_const 'TestJob', (Class.new(ActiveJob::Base) do
      def perform(feline = nil, canine: nil)
      end
    end)
    stub_const 'TestJob::Error', Class.new(StandardError)
  end

  let!(:tail_execution) do
    active_job_id = SecureRandom.uuid
    GoodJob::Execution.create!(
      active_job_id: SecureRandom.uuid,
      created_at: 1.minute.ago,
      queue_name: 'mice',
      priority: 10,
      serialized_params: {
        'job_id' => active_job_id,
        'job_class' => 'TestJob',
        'executions' => 0,
        'queue_name' => 'mice',
        'priority' => 10,
        'arguments' => ['cat', { 'canine' => 'dog' }],
      }
    )
  end

  let!(:head_execution) do
    GoodJob::Execution.create!(
      active_job_id: tail_execution.active_job_id,
      scheduled_at: 10.minutes.from_now,
      queue_name: 'mice',
      priority: 10,
      serialized_params: {
        'job_id' => tail_execution.active_job_id,
        'job_class' => 'TestJob',
        'executions' => 1,
        'exception_executions' => { 'TestJob::Error' => 1 },
        'queue_name' => 'mice',
        'priority' => 10,
        'arguments' => ['cat', { 'canine' => 'dog' }],
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
          eagerloaded_job = described_class.where(active_job_id: job.id).includes_advisory_locks.first
          expect(eagerloaded_job).to be_running
        end
      end
    end

    it 'is true if the job is Advisory Locked' do
      job.with_advisory_lock do
        job_with_locktype = described_class.where(active_job_id: job.id).includes_advisory_locks.first
        expect(job_with_locktype).to be_running
      end
    end
  end

  describe '#retry_job' do
    context 'when job is discarded' do
      before do
        head_execution.update!(
          finished_at: Time.current,
          error: "TestJob::Error: TestJob::Error"
        )
      end

      it 'enqueues another execution and updates the original job' do
        original_head_execution = job.head_execution

        expect do
          job.retry_job
        end.to change { job.executions.reload.size }.by(1)

        new_head_execution = job.head_execution(reload: true)
        expect(new_head_execution.serialized_params).to include(
          "executions" => 2,
          "queue_name" => "mice",
          "priority" => 10,
          "arguments" => ['cat', hash_including('canine' => 'dog')]
        )

        original_head_execution.reload
        expect(original_head_execution.retried_good_job_id).to eq new_head_execution.id
      end
    end

    context 'when job is already locked' do
      it 'raises an Error' do
        ActiveRecord::Base.clear_active_connections!
        job.with_advisory_lock do
          expect do
            Concurrent::Promises.future(job, &:retry_job).value!
          end.to raise_error GoodJob::Lockable::RecordAlreadyAdvisoryLockedError
        end
      end
    end

    context 'when job is not discarded' do
      it 'raises an ActionForStateMismatchError' do
        expect(job.reload.status).not_to eq :discarded
        expect { job.retry_job }.to raise_error GoodJob::ActiveJobJob::ActionForStateMismatchError
      end
    end
  end

  describe '#discard_job' do
    context 'when a job is unfinished' do
      it 'discards the job with a DiscardJobError' do
        expect do
          job.discard_job("Discarded in test")
        end.to change { job.reload.status }.from(:scheduled).to(:discarded)

        expect(job.head_execution(reload: true)).to have_attributes(
          error: "GoodJob::ActiveJobJob::DiscardJobError: Discarded in test",
          finished_at: within(1.second).of(Time.current)
        )
      end
    end

    context 'when a job is not in scheduled/queued state' do
      before do
        job.head_execution.update! finished_at: Time.current
      end

      it 'raises an ActionForStateMismatchError' do
        expect(job.reload.status).to eq :finished
        expect { job.discard_job("Discard in test") }.to raise_error GoodJob::ActiveJobJob::ActionForStateMismatchError
      end
    end
  end

  describe '#reschedule_job' do
    context 'when a job is scheduled' do
      it 'reschedules the job to right now by default' do
        expect do
          job.reschedule_job
        end.to change { job.reload.status }.from(:scheduled).to(:queued)

        expect(job.head_execution(reload: true)).to have_attributes(
          scheduled_at: within(1.second).of(Time.current)
        )
      end
    end

    context 'when a job is not in scheduled/queued state' do
      before do
        job.head_execution.update! finished_at: Time.current
      end

      it 'raises an ActionForStateMismatchError' do
        expect(job.reload.status).to eq :finished
        expect { job.reschedule_job }.to raise_error GoodJob::ActiveJobJob::ActionForStateMismatchError
      end
    end
  end
end
