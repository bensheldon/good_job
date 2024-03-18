# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Adapter Integration' do
  let(:adapter) { GoodJob::Adapter.new(execution_mode: :external) }

  around do |example|
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = adapter
    example.run
    ActiveJob::Base.queue_adapter = original_adapter
  end

  before do
    stub_const "RUN_JOBS", Concurrent::Array.new
    stub_const 'TestJob', (Class.new(ActiveJob::Base) do
      self.queue_name = 'test'
      self.priority = 50

      def perform(*_args, **_kwargs)
        RUN_JOBS << provider_job_id
      end
    end)
  end

  after do
    adapter.shutdown
  end

  describe 'enqueuing jobs' do
    describe '#perform_later' do
      it 'assigns a provider_job_id' do
        enqueued_job = TestJob.perform_later
        execution = GoodJob::Execution.find(enqueued_job.provider_job_id)

        expect(enqueued_job.provider_job_id).to eq execution.id
      end

      it 'assigns successfully_enqueued' do
        ok_job = TestJob.new
        expect { ok_job.enqueue }.not_to raise_error
        expect(ok_job.successfully_enqueued?).to be true if ok_job.respond_to?(:successfully_enqueued?)

        allow(TestJob.queue_adapter).to receive(:enqueue).and_raise(StandardError)

        bad_job = TestJob.new
        expect { bad_job.enqueue }.to raise_error(StandardError)
        expect(bad_job.successfully_enqueued?).to be false if bad_job.respond_to?(:successfully_enqueued?)
      end

      it 'without a scheduled time' do
        expect do
          TestJob.perform_later('first', 'second', keyword_arg: 'keyword_arg')
        end.to change(GoodJob::Execution, :count).by(1)

        execution = GoodJob::Execution.last
        expect(execution).to be_present
        expect(execution).to have_attributes(
          queue_name: 'test',
          priority: 50,
          scheduled_at: within(1).of(Time.current)
        )
      end

      it 'with a scheduled time' do
        expect do
          TestJob.set(wait: 1.minute, priority: 100).perform_later('first', 'second', keyword_arg: 'keyword_arg')
        end.to change(GoodJob::Execution, :count).by(1)

        execution = GoodJob::Execution.last
        expect(execution).to have_attributes(
          queue_name: 'test',
          priority: 100,
          scheduled_at: be_within(1.second).of(1.minute.from_now)
        )
      end
    end

    describe 'transactional integrity' do
      it 'does not enqueue the job when the transaction is rolled back' do
        stub_const "CustomError", Class.new(StandardError)
        TestJob.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)

        subscriber = instance_double(Proc, call: nil)
        notifier = GoodJob::Notifier.new(subscriber)
        wait_until { notifier.listening? }

        expect do
          ApplicationRecord.transaction do
            TestJob.perform_later
            raise CustomError
          end
        rescue CustomError
          nil
        end.not_to change(GoodJob::Job, :count)

        sleep 0.5
        expect(subscriber).not_to have_received(:call)

        notifier.shutdown
      end
    end
  end

  describe 'Async execution mode' do
    let(:capsule) { GoodJob::Capsule.new(configuration: GoodJob::Configuration.new({ max_threads: 5, queue_string: '*' })) }
    let(:adapter) { GoodJob::Adapter.new(execution_mode: :async_all, _capsule: capsule) }

    it 'executes the job', :skip_if_java do
      elephant_ajob = TestJob.set(queue: 'elephants').perform_later

      sleep_until { RUN_JOBS.include? elephant_ajob.provider_job_id }

      expect(RUN_JOBS).to include(elephant_ajob.provider_job_id)
    end
  end

  context 'when inline adapter' do
    let(:adapter) { GoodJob::Adapter.new(execution_mode: :inline) }

    before do
      stub_const 'PERFORMED', []
      stub_const 'JobError', Class.new(StandardError)
      stub_const 'TestJob', (Class.new(ActiveJob::Base) do
        retry_on JobError, attempts: 3, wait: 1.minute

        def perform
          PERFORMED << Time.current
          raise JobError
        end
      end)
    end

    it 'executes unscheduled jobs immediately' do
      TestJob.perform_later
      expect(PERFORMED.size).to eq 1
    end

    it 'raises unhandled exceptions' do
      expect do
        TestJob.perform_later
        2.times do
          Timecop.travel(5.minutes)
          GoodJob.perform_inline
        end
        Timecop.return
      end.to raise_error JobError
      expect(PERFORMED.size).to eq 3
    end

    describe 'immediate retries' do
      before do
        stub_const "TestJob", (Class.new(ActiveJob::Base) do
          retry_on JobError, wait: 0, attempts: Float::INFINITY

          def perform
            raise JobError if executions < 3
          end
        end)
      end

      it 'retries immediately' do
        TestJob.perform_later

        expect(GoodJob::Job.count).to eq 1
        job = GoodJob::Job.first

        expect(job.status).to eq :succeeded
        expect(job.discrete_executions.count).to eq 3
      end

      it 'retries immediately when bulk enqueued' do
        active_jobs = [TestJob.new, TestJob.new]
        adapter.enqueue_all(active_jobs)

        expect(GoodJob::Job.count).to eq 2
        expect(GoodJob::Job.all.to_a).to all have_attributes(status: :succeeded, executions_count: 3)
      end
    end
  end
end
