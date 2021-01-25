require 'rails_helper'

RSpec.describe 'Schedule Integration' do
  before do
    ActiveJob::Base.queue_adapter = adapter

    stub_const "RUN_JOBS", Concurrent::Array.new
    stub_const "THREAD_JOBS", Concurrent::Hash.new(Concurrent::Array.new)

    stub_const 'ExampleJob', (Class.new(ApplicationJob) do
      self.queue_name = 'test'
      self.priority = 50

      def perform(*_args, **_kwargs)
        thread_name = Thread.current.name || Thread.current.object_id

        RUN_JOBS << [provider_job_id, job_id, thread_name]
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
    let(:number_of_jobs) { 1000 }
    let(:max_threads) { 5 }

    let!(:good_jobs) do
      number_of_jobs.times do |i|
        ExampleJob.perform_later(i)
      end
    end

    it 'pops items off of the queue and runs them' do
      performer = GoodJob::JobPerformer.new('*')
      scheduler = GoodJob::Scheduler.new(performer, max_threads: max_threads)
      max_threads.times { scheduler.create_thread }

      sleep_until(max: 30, increments_of: 0.5) { GoodJob::Job.count == 0 }
      scheduler.shutdown

      expect(GoodJob::Job.count).to eq(0), -> { "Unworked jobs are #{GoodJob::Job.all.map(&:id)}" }
      expect(RUN_JOBS.size).to eq(number_of_jobs), lambda {
        jobs_tally = RUN_JOBS.each_with_object(Hash.new(0)) do |(provider_job_id, _job_id, _thread_name), hash|
          hash[provider_job_id] += 1
        end

        rerun_provider_job_ids = jobs_tally.select { |_key, value| value > 1 }.keys
        rerun_jobs = RUN_JOBS.select { |(provider_job_id, _job_id, _thread_name)| rerun_provider_job_ids.include? provider_job_id }

        "Expected run jobs(#{RUN_JOBS.size}) to equal number of jobs (#{number_of_jobs}). Instead ran jobs multiple times:\n#{PP.pp(rerun_jobs, '')}"
      }
    end
  end

  context 'when job has errors' do
    let!(:jobs) { ErrorJob.perform_later }

    it "handles and retries jobs with errors" do
      performer = GoodJob::JobPerformer.new('*')
      scheduler = GoodJob::Scheduler.new(performer)
      scheduler.create_thread

      sleep_until(max: 5, increments_of: 0.5) { GoodJob::Job.count == 0 }

      scheduler.shutdown
    end
  end

  context 'when there are existing and future scheduled jobs' do
    before do
      2.times { ExampleJob.set(wait_until: 5.minutes.ago).perform_later }
      2.times { ExampleJob.set(wait_until: 2.seconds.from_now).perform_later }
    end

    it 'warms up and schedules them in a cache' do
      performer = GoodJob::JobPerformer.new('*')
      scheduler = GoodJob::Scheduler.new(performer, max_threads: 5, max_cache: 5)
      sleep_until(max: 5, increments_of: 0.5) { GoodJob::Job.count == 0 }
      scheduler.shutdown
    end
  end
end
