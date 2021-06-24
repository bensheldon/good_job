require 'rails_helper'

RSpec.describe 'Schedule Integration' do
  let(:adapter) { GoodJob::Adapter.new(execution_mode: :external) }

  before do
    ActiveJob::Base.queue_adapter = adapter
  end

  context 'when there are a large number of jobs' do
    let(:number_of_jobs) { 500 }
    let(:max_threads) { 5 }

    let!(:good_jobs) do
      GoodJob::Job.transaction do
        number_of_jobs.times do |i|
          ExampleJob.perform_later(i)
        end
      end
    end

    it 'pops items off of the queue and runs them' do
      performer = GoodJob::JobPerformer.new('*')
      scheduler = GoodJob::Scheduler.new(performer, max_threads: max_threads)
      max_threads.times { scheduler.create_thread }

      sleep_until(max: 30, increments_of: 0.5) { GoodJob::Job.count == 0 }
      scheduler.shutdown

      expect(GoodJob::Job.count).to eq(0), -> { "Unworked jobs are #{GoodJob::Job.all.map(&:id)}" }
      expect(ExampleJob::RUN_JOBS.size).to eq(number_of_jobs), lambda {
        jobs_tally = ExampleJob::RUN_JOBS.each_with_object(Hash.new(0)) do |(provider_job_id, _job_id, _thread_name), hash|
          hash[provider_job_id] += 1
        end

        rerun_provider_job_ids = jobs_tally.select { |_key, value| value > 1 }.keys
        rerun_jobs = ExampleJob::RUN_JOBS.select { |(provider_job_id, _job_id, _thread_name)| rerun_provider_job_ids.include? provider_job_id }

        "Expected run jobs(#{ExampleJob::RUN_JOBS.size}) to equal number of jobs (#{number_of_jobs}). Instead ran jobs multiple times:\n#{PP.pp(rerun_jobs, '')}"
      }
    end
  end

  context 'when a single thread' do
    let(:max_threads) { 1 }
    let(:number_of_jobs) { 50 }

    let!(:good_jobs) do
      GoodJob::Job.transaction do
        number_of_jobs.times do |i|
          ExampleJob.perform_later(i)
        end
      end
    end

    it 'executes all jobs' do
      performer = GoodJob::JobPerformer.new('*')
      scheduler = GoodJob::Scheduler.new(performer, max_threads: max_threads)
      scheduler.create_thread

      sleep_until(max: 10, increments_of: 0.5) do
        GoodJob::Job.count == 0
      end
      scheduler.shutdown
    end
  end

  context 'when job has errors' do
    let!(:jobs) { ExampleJob.perform_later(raise_error: :retryable) }

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
      scheduler.warm_cache
      sleep_until(max: 5, increments_of: 0.5) { GoodJob::Job.count == 0 }
      scheduler.shutdown
    end
  end
end
