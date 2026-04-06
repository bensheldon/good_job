# frozen_string_literal: true

require 'rails_helper'

describe GoodJob::Batch do
  before do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
    stub_const 'TestJob', (Class.new(ActiveJob::Base) do
      def perform
      end
    end)
    stub_const 'CallbackJob', (Class.new(ActiveJob::Base) do
      def perform(batch, params)
      end
    end)

    stub_const 'DiscardOnceJob', (Class.new(ActiveJob::Base) do
      discard_on StandardError

      def perform
        raise StandardError if executions == 1
      end
    end)
  end

  it 'is a valid GlobalId' do
    batch = described_class.new
    batch.save

    global_id = batch.to_global_id
    returned_batch = GlobalID::Locator.locate(global_id)

    expect(returned_batch.id).to eq batch.id
  end

  describe '.enqueue' do
    it 'creates a batch' do
      batch = described_class.enqueue do
        TestJob.perform_later
        TestJob.perform_later
      end

      expect(batch).to be_persisted
      expect(batch.enqueued_at).to be_within(1.second).of(Time.current)
      expect(batch.active_jobs.count).to eq 2
    end

    it 'resets callbacks' do
      batch = described_class.new(on_finish: "CallbackJob")
      batch.enqueue { TestJob.perform_later }  # 1st time triggers callback
      GoodJob.perform_inline
      batch.enqueue { TestJob.perform_later }  # 2nd time does not trigger callback (finished_at didn't update to nil on the stale reference to batch_record)
      GoodJob.perform_inline

      expect(batch.callback_active_jobs.count).to eq 2
    end
  end

  describe '.enqueue_all' do
    it 'returns an array of batches' do
      pairs = Array.new(2) { [described_class.new, [TestJob.new]] }
      result = described_class.enqueue_all(pairs)

      expect(result).to be_an(Array)
      expect(result.size).to eq 2
      expect(result).to all be_a(described_class)
    end

    it 'creates batch records in the database' do
      pairs = Array.new(3) { [described_class.new, [TestJob.new]] }

      expect { described_class.enqueue_all(pairs) }
        .to change(GoodJob::BatchRecord, :count).by(3)
    end

    it 'creates job records with correct batch_id' do
      batch_1 = described_class.new
      batch_2 = described_class.new
      job_1 = TestJob.new
      job_2 = TestJob.new
      job_3 = TestJob.new

      described_class.enqueue_all([[batch_1, [job_1]], [batch_2, [job_2, job_3]]])

      expect(GoodJob::Job.where(batch_id: batch_1.id).count).to eq 1
      expect(GoodJob::Job.where(batch_id: batch_2.id).count).to eq 2
    end

    it 'sets enqueued_at on all batches' do
      pairs = Array.new(2) { [described_class.new, [TestJob.new]] }
      batches = described_class.enqueue_all(pairs)

      batches.each do |batch|
        expect(batch.enqueued_at).to be_within(1.second).of(Time.current)
      end
    end

    it 'sets provider_job_id on all ActiveJob instances' do
      jobs = [TestJob.new, TestJob.new]
      described_class.enqueue_all([[described_class.new, jobs]])

      jobs.each do |job|
        expect(job.provider_job_id).to be_present
      end
    end

    it 'marks batches as persisted' do
      batch = described_class.new
      described_class.enqueue_all([[batch, [TestJob.new]]])

      expect(batch).to be_persisted
      expect(batch.id).to be_present
    end

    it 'handles empty input' do
      result = described_class.enqueue_all([])
      expect(result).to eq []
    end

    it 'raises ArgumentError for already-persisted batches' do
      batch = described_class.new
      batch.save

      expect do
        described_class.enqueue_all([[batch, [TestJob.new]]])
      end.to raise_error(ArgumentError, /not persisted/)
    end

    it 'handles batch properties' do
      batch = described_class.new(properties: { foo: 'bar', count: 42 })
      described_class.enqueue_all([[batch, [TestJob.new]]])

      reloaded = described_class.find(batch.id)
      expect(reloaded.properties).to eq({ foo: 'bar', count: 42 })
    end

    it 'handles callback configuration' do
      batch = described_class.new
      batch.on_finish = "CallbackJob"
      batch.on_success = "CallbackJob"
      batch.on_discard = "CallbackJob"
      batch.callback_queue_name = "callbacks"
      batch.callback_priority = 5

      described_class.enqueue_all([[batch, [TestJob.new]]])

      reloaded = described_class.find(batch.id)
      expect(reloaded).to have_attributes(
        on_finish: "CallbackJob",
        on_success: "CallbackJob",
        on_discard: "CallbackJob",
        callback_queue_name: "callbacks",
        callback_priority: 5
      )
    end

    it 'handles job options (queue, priority)' do
      job = TestJob.new
      job.queue_name = "high_priority"
      job.priority = 1

      described_class.enqueue_all([[described_class.new, [job]]])

      good_job = GoodJob::Job.find_by(active_job_id: job.job_id)
      expect(good_job).to have_attributes(
        queue_name: "high_priority",
        priority: 1
      )
    end

    it 'handles description attribute' do
      batch = described_class.new
      batch.description = "Test batch"
      described_class.enqueue_all([[batch, [TestJob.new]]])

      reloaded = described_class.find(batch.id)
      expect(reloaded.description).to eq "Test batch"
    end

    it 'handles mixed batches: some with jobs, some empty' do
      batch_1 = described_class.new
      batch_2 = described_class.new

      described_class.enqueue_all([
                                    [batch_1, [TestJob.new, TestJob.new]],
                                    [batch_2, []],
                                  ])

      expect(GoodJob::Job.where(batch_id: batch_1.id).count).to eq 2
      expect(GoodJob::Job.where(batch_id: batch_2.id).count).to eq 0
      expect(batch_1).to be_persisted
      expect(batch_2).to be_persisted
    end

    context 'with empty batches' do
      it 'triggers callbacks for batches with zero jobs' do
        batch = described_class.new
        batch.on_finish = "CallbackJob"

        described_class.enqueue_all([[batch, []]])

        GoodJob.perform_inline

        batch.reload
        expect(batch.callback_active_jobs.size).to eq 1
      end
    end

    context 'with concurrency-limited jobs' do
      before do
        stub_const 'ConcurrencyJob', (Class.new(ActiveJob::Base) do
          include GoodJob::ActiveJobExtensions::Concurrency

          good_job_control_concurrency_with(
            total_limit: 1,
            key: -> { "concurrency_test" }
          )

          def perform
          end
        end)
      end

      it 'enqueues concurrency-limited jobs individually with batch_id' do
        batch = described_class.new
        jobs = [ConcurrencyJob.new, TestJob.new]

        described_class.enqueue_all([[batch, jobs]])

        expect(GoodJob::Job.where(batch_id: batch.id).count).to eq 2
      end

      it 'respects concurrency limits by running before_enqueue checks' do
        batch = described_class.new
        job_1 = ConcurrencyJob.new
        job_2 = ConcurrencyJob.new

        described_class.enqueue_all([[batch, [job_1, job_2]]])

        # total_limit: 1 means only the first should succeed;
        # the second is silently dropped (matching Bulk::Buffer behavior).
        expect(GoodJob::Job.where(batch_id: batch.id).count).to eq 1
      end
    end
  end

  describe '#add' do
    let(:batch) { described_class.new }

    it 'preserves the batch' do
      batch.add do
        TestJob.perform_later
        TestJob.perform_later
      end

      expect(batch).to be_persisted
      expect(batch.active_jobs.count).to eq 2
    end
  end

  describe '#enqueue' do
    let(:batch) { described_class.new }

    it 'marks the job as enqueued' do
      batch.enqueue do
        TestJob.perform_later
        TestJob.perform_later
      end

      expect(batch.active_jobs.count).to eq 2
      expect(batch.enqueued_at).to be_present
    end

    it 'can be used without a block' do
      expect { batch.enqueue }.to change(batch, :enqueued_at).from(nil)
    end

    it 'does updates the enqueued_at and clears finished_at' do
      batch._record.update(enqueued_at: 1.day.ago, finished_at: 1.day.ago)
      expect { batch.enqueue(TestJob.new) }.to change(batch, :enqueued_at).and change(batch, :finished_at).to(nil)
    end

    it 'can assign callback jobs' do
      batch = described_class.new
      batch.enqueue(on_finish: TestJob, on_success: TestJob, on_discard: TestJob)

      expect(batch.on_finish).to eq "TestJob"
      expect(batch.on_success).to eq "TestJob"
      expect(batch.on_discard).to eq "TestJob"
    end
  end

  describe '#retry' do
    let(:batch) { described_class.new }

    it 'retries discarded jobs' do
      batch.enqueue do
        TestJob.perform_later
        DiscardOnceJob.perform_later
      end

      GoodJob.perform_inline

      expect(batch.reload).to be_discarded
      expect(batch).to have_attributes(discarded_at: be_present, jobs_finished_at: be_present, finished_at: be_present)

      batch.retry

      batch.reload
      expect(batch).to have_attributes(discarded_at: nil, jobs_finished_at: nil, finished_at: nil)
      expect(batch).to be_enqueued

      GoodJob.perform_inline

      batch.reload
      expect(batch).to have_attributes(discarded_at: nil, jobs_finished_at: be_present, finished_at: be_present)
      expect(batch).to be_succeeded
    end
  end

  describe '#properties' do
    it 'defaults to an empty hash' do
      batch = described_class.new
      expect(batch.properties).to eq({})
    end

    it 'serializes and deserializes values' do
      batch = described_class.new(properties: { foo: 'bar' })
      batch.save
      reloaded_batch = described_class.find(batch.id)

      expect(reloaded_batch.properties).to eq({ foo: 'bar' })
    end

    it 'can modify values and they are saved' do
      batch = described_class.new(foo: 'bar')
      batch.save
      batch.properties[:foo] = 'baz'
      batch.save

      reloaded_batch = described_class.find(batch.id)
      expect(reloaded_batch.properties).to eq({ foo: 'baz' })
      reloaded_batch.properties[:foo] = 'quz'
      reloaded_batch.save

      batch.reload
      expect(batch.properties).to eq({ foo: 'quz' })
      batch.properties.clear
      batch.save

      reloaded_batch.reload
      expect(reloaded_batch.properties).to eq({})
    end

    it 'can serialize GlobalId objects' do
      globalid = GoodJob::Job.create!

      batch = described_class.new
      batch.save

      batch.properties[:globalid] = globalid
      batch.save
      expect(batch.properties[:globalid]).to eq globalid

      reloaded_batch = described_class.find(batch.id)
      expect(reloaded_batch.properties).to eq({ globalid: globalid })
    end
  end

  describe 'callbacks' do
    before do
      stub_const 'CallbackJob', (Class.new(ActiveJob::Base) do
        def perform(_batch, _options)
          nil
        end
      end)
    end

    describe '#on_finish' do
      it 'is enqueued' do
        batch = described_class.new
        batch.on_finish = "CallbackJob"
        batch.enqueue

        expect(batch.callback_active_jobs.size).to eq 1
      end
    end
  end

  describe '#active_jobs' do
    it 'returns associated Active Jobs' do
      batch = described_class.enqueue do
        TestJob.perform_later
        TestJob.perform_later
      end
      expect(batch.active_jobs.count).to eq 2
      expect(batch.active_jobs).to all be_a(TestJob)
    end
  end
end
