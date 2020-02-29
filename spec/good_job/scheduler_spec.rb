require 'rails_helper'

RSpec.describe GoodJob::Scheduler do
  around do |example|
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = adapter
    example.run
    ActiveJob::Base.queue_adapter = original_adapter
  end

  before do
    stub_const "RUN_JOBS", Concurrent::Array.new
    stub_const "THREAD_JOBS", Concurrent::Hash.new(Concurrent::Array.new)

    stub_const 'ExampleJob', (Class.new(ApplicationJob) do
      self.queue_name = 'test'
      self.priority = 50

      def perform(*args, **kwargs)
        thread_name = Thread.current.name || Thread.current.object_id

        RUN_JOBS << { args: args, kwargs: kwargs }
        THREAD_JOBS[thread_name] << provider_job_id
      end
    end)
  end

  let(:adapter) { GoodJob::Adapter.new }

  let(:number_of_jobs) { 250 }

  let!(:good_jobs) do
    number_of_jobs.times do |i|
      ExampleJob.perform_later(i)
    end
  end

  it 'pops items off of the queue and runs them' do
    scheduler = GoodJob::Scheduler.new

    Timeout.timeout(5) do
      sleep(0.5) until GoodJob::Job.count == 0
    end

    if RUN_JOBS.size != number_of_jobs
      jobs = THREAD_JOBS.values.flatten

      jobs_tally = jobs.each_with_object(Hash.new(0)) do |job_id, hash|
        hash[job_id] += 1
      end

      rerun_jobs = jobs_tally.select { |key, value| value > 1 }

      rerun_jobs.each do |job_id, tally|
        rerun_threads = THREAD_JOBS.select { |thread, jobs| jobs.include? job_id }.keys

        puts "Ran job id #{job_id} for #{tally} times on threads #{rerun_threads}"
      end
    end

    scheduler.shutdown

    expect(GoodJob::Job.count).to eq(0), -> { "Unworked jobs are #{GoodJob::Job.all.map(&:id)}" }
    expect(rerun_jobs).to be_nil
    expect(RUN_JOBS.size).to eq number_of_jobs
  end
end
