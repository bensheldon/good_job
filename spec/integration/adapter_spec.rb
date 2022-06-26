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

      it 'without a scheduled time' do
        expect do
          TestJob.perform_later('first', 'second', keyword_arg: 'keyword_arg')
        end.to change(GoodJob::Execution, :count).by(1)

        execution = GoodJob::Execution.last
        expect(execution).to be_present
        expect(execution).to have_attributes(
          queue_name: 'test',
          priority: 50,
          scheduled_at: nil
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
  end

  describe 'Async execution mode' do
    let(:adapter) { GoodJob::Adapter.new execution_mode: :async_all }

    it 'executes the job', skip_if_java: true do
      elephant_adapter = GoodJob::Adapter.new execution_mode: :async_all
      elephant_ajob = TestJob.set(queue: 'elephants').perform_later

      sleep_until { RUN_JOBS.include? elephant_ajob.provider_job_id }

      expect(RUN_JOBS).to include(elephant_ajob.provider_job_id)

      elephant_adapter.shutdown
    end
  end

  context 'when inline adapter' do
    let(:adapter) { GoodJob::Adapter.new(execution_mode: :inline) }

    before do
      stub_const 'PERFORMED', []
      stub_const 'JobError', Class.new(StandardError)
      stub_const 'TestJob', (Class.new(ActiveJob::Base) do
        retry_on JobError, attempts: 3

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
        5.times do
          travel(5.minutes)
          GoodJob.perform_inline
        end
        travel_back
      end.to raise_error JobError
      expect(PERFORMED.size).to eq 3
    end
  end
end
