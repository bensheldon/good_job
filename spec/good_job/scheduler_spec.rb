require 'rails_helper'

RSpec.describe GoodJob::Scheduler do
  before do
    ActiveJob::Base.queue_adapter = adapter

    stub_const "RUN_JOBS", Concurrent::Array.new
    stub_const "THREAD_JOBS", Concurrent::Hash.new(Concurrent::Array.new)

    stub_const 'ExampleJob', (Class.new(ApplicationJob) do
      self.queue_name = 'test'
      self.priority = 50

      def perform(*_args, **_kwargs)
        thread_name = Thread.current.name || Thread.current.object_id

        RUN_JOBS << provider_job_id
        THREAD_JOBS[thread_name] << provider_job_id
      end
    end)

    stub_const 'RetryableError', Class.new(StandardError)
    stub_const 'ErrorJob', (Class.new(ApplicationJob) do
      self.queue_name = 'test'
      self.priority = 50
      retry_on(RetryableError, wait: 0, attempts: 3) do |job, error|
        # puts "FAILED"
      end

      def perform(*args, **kwargs)
        thread_name = Thread.current.name || Thread.current.object_id

        RUN_JOBS << { args: args, kwargs: kwargs }
        THREAD_JOBS[thread_name] << provider_job_id

        raise RetryableError
      end
    end), transfer_nested_constants: true
  end

  let(:adapter) { GoodJob::Adapter.new }

  context 'when there are a large number of jobs' do
    let(:number_of_jobs) { 250 }

    let!(:good_jobs) do
      number_of_jobs.times do |i|
        ExampleJob.perform_later(i)
      end
    end

    it 'pops items off of the queue and runs them' do
      scheduler = described_class.new(GoodJob::Job.all.to_performer)
      sleep_until(max: 5, increments_of: 0.5) { GoodJob::Job.count == 0 }

      if RUN_JOBS.size != number_of_jobs
        jobs = THREAD_JOBS.values.flatten

        jobs_tally = jobs.each_with_object(Hash.new(0)) do |job_id, hash|
          hash[job_id] += 1
        end

        rerun_jobs = jobs_tally.select { |_key, value| value > 1 }

        rerun_jobs.each do |job_id, tally|
          rerun_threads = THREAD_JOBS.select { |_thread, thread_jobs| thread_jobs.include? job_id }.keys

          puts "Ran job id #{job_id} for #{tally} times on threads #{rerun_threads}"
        end
      end

      scheduler.shutdown

      expect(GoodJob::Job.count).to eq(0), -> { "Unworked jobs are #{GoodJob::Job.all.map(&:id)}" }
      expect(rerun_jobs).to be_nil
      expect(RUN_JOBS.size).to eq number_of_jobs
    end
  end

  context 'when job has errors' do
    let!(:jobs) { ErrorJob.perform_later }

    it "handles and retries jobs with errors" do
      scheduler = described_class.new(GoodJob::Job.all.to_performer)

      sleep_until(max: 5, increments_of: 0.5) { GoodJob::Job.count == 0 }

      scheduler.shutdown
    end
  end
end
