# frozen_string_literal: true
require 'rails_helper'

describe GoodJob::Bulk do
  before do
    stub_const 'TestJob', (Class.new(ActiveJob::Base) do
      def perform
        true
      end
    end)
    TestJob.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
  end

  describe '.capture' do
    describe 'when a block is used' do
      it 'restores the previous buffer when the block completes' do
        described_class.capture do
          expect { described_class.capture { true } }.not_to change(described_class, :current_buffer)
        end
      end

      it 'returns the active jobs that were captured' do
        result = described_class.capture { TestJob.perform_later }
        expect(result).to contain_exactly instance_of(TestJob)
      end
    end

    describe 'when no block is used' do
      it 'returns a truthy value when there is a buffer' do
        described_class.capture do
          expect(described_class.capture(TestJob.new)).to be_truthy
        end
      end

      it 'returns a falsey value when there is no buffer' do
        result = described_class.capture(TestJob.new)
        expect(result).to be_falsey
      end
    end
  end

  describe '.enqueue' do
    it 'enqueues multiple jobs at once' do
      described_class.enqueue do
        TestJob.perform_later
        expect(GoodJob::Job.count).to eq 0

        TestJob.perform_later
        expect(GoodJob::Job.count).to eq 0
      end

      expect(GoodJob::Job.count).to eq 2
    end

    it 'does not enqueue jobs if there is an error' do
      expect do
        described_class.enqueue do
          TestJob.perform_later
          TestJob.perform_later
          raise 'error'
        end
      end.to raise_error('error')

      expect(GoodJob::Job.count).to eq 0
    end

    it 'returns the Active Jobs that were enqueued' do
      active_jobs = described_class.enqueue do
        TestJob.perform_later
        TestJob.perform_later
      end

      expect(active_jobs.count).to eq 2
      expect(active_jobs.first).to be_a TestJob
      expect(active_jobs.first.provider_job_id).to be_present
    end

    it 'can enqueue Active Jobs directly' do
      active_jobs = [TestJob.new, TestJob.new]
      result = described_class.enqueue(active_jobs)

      expect(result).to eq active_jobs

      # Expect active_jobs to all have provider_job_id
      expect(active_jobs.all?(&:provider_job_id)).to be true
    end

    it 'does not re-enqueue Active Jobs that have already been enqueued' do
      active_job = TestJob.new
      active_job.provider_job_id = 1

      expect do
        described_class.enqueue(active_job)
      end.not_to change(active_job, :provider_job_id)
    end

    it 'can handle non-GoodJob jobs that are directly inserted into the buffer' do
      adapter = instance_double(ActiveJob::QueueAdapters::InlineAdapter, enqueue: nil, enqueue_at: nil)
      TestJob.queue_adapter = adapter

      described_class.enqueue(TestJob.new)
      expect(GoodJob::Job.count).to eq 0
      expect(adapter).to have_received(:enqueue).once
    end

    it 'does not enqueue jobs that fail enqueue concurrency' do
      TestJob.include(GoodJob::ActiveJobExtensions::Concurrency)

      TestJob.good_job_control_concurrency_with(total_limit: 1, key: 'test')
      job_1 = TestJob.new
      job_2 = TestJob.new

      described_class.enqueue([job_1, job_2])
      expect(job_1.provider_job_id).to be_present
      expect(job_2.provider_job_id).to be_nil
    end
  end
end
