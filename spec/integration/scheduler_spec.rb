# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'Schedule Integration' do
  let(:adapter) { GoodJob::Adapter.new(execution_mode: :external) }

  before do
    ActiveJob::Base.queue_adapter = adapter
    GoodJob.preserve_job_records = true

    stub_const "RUN_JOBS", Concurrent::Array.new
    stub_const "THREAD_JOBS", Concurrent::Hash.new(Concurrent::Array.new)

    stub_const 'TestJob', (Class.new(ActiveJob::Base) do
      self.queue_name = 'test'
      self.priority = 50

      def perform(*_args, **_kwargs)
        thread_name = Thread.current.name || Thread.current.object_id

        expected_locks_per_thread = 1
        locks_count = PgLock.advisory_lock.owns.count

        if locks_count > expected_locks_per_thread
          puts "Thread #{thread_name} owns #{locks_count} locks."

          puts "GoodJobs locked by this connection:"
          GoodJob::Execution.owns_advisory_locked.select('good_jobs.id', 'good_jobs.active_job_id', 'pg_locks.*').each do |execution|
            puts "  - GoodJob #{execution.id} / ActiveJob #{execution.active_job_id} / #{execution.attributes.to_json}"
          end

          puts "All advisory locks by this connection:"
          PgLock.advisory_lock.owns.each do |pg_lock|
            puts "  -  #{pg_lock.attributes.to_json}"
          end
        end

        RUN_JOBS << [provider_job_id, job_id, thread_name]
        THREAD_JOBS[thread_name] << provider_job_id
      end
    end)

    stub_const 'RetryableError', Class.new(StandardError)
    stub_const 'ErrorJob', (Class.new(ActiveJob::Base) do
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

  context 'when there are a large number of jobs' do
    let(:number_of_jobs) { 500 }
    let(:max_threads) { 5 }

    it 'pops items off of the queue and runs them' do
      expect(ActiveJob::Base.queue_adapter).to be_execute_externally

      GoodJob::Execution.transaction do
        number_of_jobs.times do |i|
          TestJob.perform_later(i)
        end
      end

      performer = GoodJob::JobPerformer.new('*')
      scheduler = GoodJob::Scheduler.new(performer, max_threads: max_threads)
      max_threads.times { scheduler.create_thread }

      sleep_until(max: 30, increments_of: 0.5) { GoodJob::Execution.unfinished.count.zero? }
      scheduler.shutdown

      expect(GoodJob::Execution.unfinished.count).to eq(0), -> { "Unworked jobs are #{GoodJob::Execution.unfinished.map(&:id)}" }
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

  context 'when a single thread' do
    let(:max_threads) { 1 }
    let(:number_of_jobs) { 50 }

    it 'executes all jobs' do
      expect(ActiveJob::Base.queue_adapter).to be_execute_externally

      GoodJob::Execution.transaction do
        number_of_jobs.times do |i|
          TestJob.perform_later(i)
        end
      end

      performer = GoodJob::JobPerformer.new('*')
      scheduler = GoodJob::Scheduler.new(performer, max_threads: max_threads)
      scheduler.create_thread

      sleep_until(max: 10, increments_of: 0.5) do
        GoodJob::Execution.unfinished.count.zero?
      end
      scheduler.shutdown
      expect(scheduler).to be_shutdown
    end
  end

  context 'when job has errors' do
    let!(:jobs) { ErrorJob.perform_later }

    it "handles and retries jobs with errors" do
      performer = GoodJob::JobPerformer.new('*')
      scheduler = GoodJob::Scheduler.new(performer)
      scheduler.create_thread

      wait_until(max: 5, increments_of: 0.5) do
        expect(GoodJob::Execution.unfinished.count).to eq 0
      end

      scheduler.shutdown
    end
  end

  context 'when there are existing and future scheduled jobs' do
    before do
      2.times { TestJob.set(wait_until: 5.minutes.ago).perform_later }
      2.times { TestJob.set(wait_until: 2.seconds.from_now).perform_later }
    end

    it 'warms up and schedules them in a cache' do
      performer = GoodJob::JobPerformer.new('*')
      scheduler = GoodJob::Scheduler.new(performer, max_threads: 5, max_cache: 5)
      scheduler.warm_cache
      sleep_until(max: 5, increments_of: 0.5) { GoodJob::Execution.unfinished.count.zero? }
      scheduler.shutdown
      expect(scheduler).to be_shutdown
    end
  end
end
