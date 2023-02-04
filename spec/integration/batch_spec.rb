# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'Batches' do
  let(:adapter) { GoodJob::Adapter.new(execution_mode: :external) }

  before do
    ActiveJob::Base.queue_adapter = adapter
    GoodJob.preserve_job_records = true

    stub_const 'ExpectedError', Class.new(StandardError)
    stub_const 'TestJob', (Class.new(ActiveJob::Base) do
      retry_on(ExpectedError, wait: 0, attempts: 2) { nil }

      def perform(error: false)
        raise ExpectedError if error
      end
    end)

    stub_const 'BatchCallbackJob', (Class.new(ActiveJob::Base) do
      def perform(batch, options)
        # nil
      end
    end)
  end

  describe 'simple batching' do
    it 'assigns a batch_id to all jobs in the batch' do
      active_job = nil
      batch = GoodJob::Batch.enqueue do
        active_job = TestJob.perform_later
      end

      good_job = GoodJob::Job.find_by(active_job_id: active_job.job_id)
      expect(good_job.batch_id).to eq batch.id
    end

    context 'when all jobs complete successfully' do
      it 'has success status' do
        batch = GoodJob::Batch.enqueue do
          TestJob.perform_later
        end

        expect(batch.finished_at).to be_nil
        expect(batch).to be_enqueued

        GoodJob.perform_inline

        batch.reload
        expect(batch).to be_finished
        expect(batch).to be_succeeded

        expect(batch.finished_at).to be_within(1.second).of(Time.current)
        expect(batch.discarded_at).to be_nil
      end
    end

    context 'when a job is discarded' do
      it "has a failure status" do
        batch = GoodJob::Batch.enqueue do
          TestJob.perform_later(error: true)
        end

        GoodJob.perform_inline

        batch.reload
        expect(batch).to be_finished
        expect(batch).to be_discarded

        expect(batch.finished_at).to be_within(1.second).of(Time.current)
        expect(batch.discarded_at).to be_within(1.second).of(Time.current)
      end
    end

    context 'when there is a callback' do
      it 'calls the callback with a batch' do
        batch = GoodJob::Batch.enqueue(description: "foobar", on_finish: "BatchCallbackJob", foo: "bar") do
          TestJob.perform_later
        end

        expect(batch.description).to eq "foobar"
        expect(batch.properties).to eq({ foo: "bar" })

        GoodJob.perform_inline

        last_job = GoodJob::Job.order(:created_at).last
        expect(last_job).to have_attributes(job_class: 'BatchCallbackJob')
        expect(last_job.error).to be_nil
      end
    end
  end

  describe 'complex batching' do
    it 'can be used as instance object' do
      batch = GoodJob::Batch.new
      batch.on_finish = "BatchCallbackJob"
      batch.callback_queue_name = "custom_queue"
      batch.callback_priority = 10

      expect(batch).not_to be_persisted
      expect(batch).not_to be_enqueued

      # addr jobs to the batch
      batch.add do
        TestJob.perform_later
      end

      expect(batch).to be_persisted
      expect(batch).not_to be_enqueued

      # it's ok for the jobs to already be run; this is heavily asynchronous
      GoodJob.perform_inline

      batch.enqueue
      expect(batch.enqueued_at).to be_within(1.second).of(Time.current)

      GoodJob.perform_inline("custom_queue") # for the callback job

      callback_job = GoodJob::Job.order(:created_at).last
      expect(callback_job).to have_attributes(
        batch_callback_id: batch.id,
        job_class: 'BatchCallbackJob',
        priority: 10,
        queue_name: "custom_queue"
      )
    end
  end

  context 'when running inline' do
    let(:adapter) { GoodJob::Adapter.new(execution_mode: :inline) }

    before do
      stub_const 'RecursiveJob', (Class.new(ActiveJob::Base) do
        def perform(recurse)
          RecursiveJob.perform_later(false) if recurse
        end
      end)
    end

    it 'does not unintentionally add sub-enqueued job to the batch' do
      batch = GoodJob::Batch.enqueue do
        RecursiveJob.perform_later(true)
      end

      expect(GoodJob::Job.count).to eq 2
      expect(batch.active_jobs.count).to eq 1
    end
  end

  describe 'complex recursive batching' do
    let(:adapter) { GoodJob::Adapter.new(execution_mode: :inline) }

    before do
      stub_const 'DONE', Concurrent::AtomicBoolean.new(false)
      stub_const 'SimpleJob', (Class.new(ActiveJob::Base) do
        def perform
        end
      end)
      stub_const 'MyBatchJob', (Class.new(ActiveJob::Base) do
        def perform(batch, _options = {})
          case batch.properties[:stage]
          when 1
            batch.enqueue(stage: 2) do
              3.times { SimpleJob.perform_later }
            end
          when 2
            batch.enqueue(stage: 3) do
              7.times { SimpleJob.perform_later }
            end
          else
            DONE.make_true
          end
        end
      end)
    end

    it 'can enqueue multiple jobs' do
      batch = GoodJob::Batch.enqueue(on_finish: "MyBatchJob", stage: 1)
      GoodJob.perform_inline

      expect(DONE.value).to be true
      expect(batch.active_jobs.count).to eq 10
      expect(batch.callback_active_jobs.count).to eq 3
    end
  end

  describe 'all callbacks are called and retryable' do
    before do
      stub_const 'RetryableError', Class.new(StandardError)
      stub_const 'DiscardableError', Class.new(StandardError)
      stub_const 'TestJob', (Class.new(ActiveJob::Base) do
        def perform(*args, **kwargs)
        end
      end)
      stub_const 'DiscardedJob', (Class.new(ActiveJob::Base) do
        discard_on 'DiscardableError'

        def perform(*_args, **_kwargs)
          raise DiscardableError
        end
      end)
      stub_const 'RetriedJob', (Class.new(ActiveJob::Base) do
        retry_on 'RetryableError', wait: 0, attempts: 2

        def perform(*_args, **_kwargs)
          raise RetryableError if executions == 1
        end
      end)
    end

    it 'calls discard callbacks' do
      batch = GoodJob::Batch.enqueue(on_finish: "RetriedJob", on_success: "RetriedJob", on_discard: "RetriedJob", user: 'Alice') do
        DiscardedJob.perform_later
      end
      GoodJob.perform_inline

      expect(GoodJob::Job.count).to eq 3
      expect(GoodJob::Execution.count).to eq 5
      expect(GoodJob::Execution.where(batch_id: batch.id).count).to eq 1
      expect(GoodJob::Execution.where(batch_callback_id: batch.id).count).to eq 4

      callback_arguments = GoodJob::Job.where(batch_callback_id: batch.id).map(&:head_execution).map(&:active_job).map(&:arguments).map(&:second)
      expect(callback_arguments).to contain_exactly({ event: :discard }, { event: :finish })
    end

    it 'calls success callbacks' do
      batch = GoodJob::Batch.enqueue(on_finish: "RetriedJob", on_success: "RetriedJob", on_discard: "RetriedJob", user: 'Alice') do
        TestJob.perform_later
      end
      GoodJob.perform_inline

      expect(GoodJob::Job.count).to eq 3
      expect(GoodJob::Execution.count).to eq 5
      expect(GoodJob::Execution.where(batch_id: batch.id).count).to eq 1
      expect(GoodJob::Execution.where(batch_callback_id: batch.id).count).to eq 4

      callback_arguments = GoodJob::Job.where(batch_callback_id: batch.id).map(&:head_execution).map(&:active_job).map(&:arguments).map(&:second)
      expect(callback_arguments).to contain_exactly({ event: :success }, { event: :finish })
    end
  end
end
