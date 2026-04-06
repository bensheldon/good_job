# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Lock strategy integration' do
  around do |example|
    original_lock_strategy = GoodJob.configuration.options[:lock_strategy]
    example.run
  ensure
    if original_lock_strategy.nil?
      GoodJob.configuration.options.delete(:lock_strategy)
    else
      GoodJob.configuration.options[:lock_strategy] = original_lock_strategy
    end
  end

  before do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
    GoodJob.preserve_job_records = true

    stub_const "RUN_JOBS", Concurrent::Array.new
    stub_const 'TestJob', (Class.new(ActiveJob::Base) do
      def perform(value = nil)
        RUN_JOBS << provider_job_id
        value
      end
    end)
  end

  shared_examples 'a lock strategy that executes jobs correctly' do |strategy|
    before do
      GoodJob.configuration.options[:lock_strategy] = strategy
    end

    it "#{strategy}: performs a single job and clears lock columns on finish" do
      TestJob.perform_later

      performer = GoodJob::JobPerformer.new('*')
      scheduler = GoodJob::Scheduler.new(performer, max_threads: 1)
      scheduler.create_thread

      wait_until(max: 5, increments_of: 0.1) do
        expect(GoodJob::Job.last.finished_at).to be_present
      end
      scheduler.shutdown

      job = GoodJob::Job.last
      expect(job).to have_attributes(
        finished_at: be_present,
        lock_type: nil,
        locked_by_id: nil,
        locked_at: nil
      )
      expect(RUN_JOBS.size).to eq 1
    end

    it "#{strategy}: executes all jobs exactly once with concurrent workers" do
      number_of_jobs = 20

      GoodJob::Job.logger.silence do
        jobs = Array.new(number_of_jobs) { TestJob.new }
        TestJob.queue_adapter.enqueue_all(jobs)
      end

      performer = GoodJob::JobPerformer.new('*')
      scheduler = GoodJob::Scheduler.new(performer, max_threads: 5)
      5.times { scheduler.create_thread }

      wait_until(max: 30, increments_of: 0.2) do
        expect(GoodJob::Job.unfinished.count).to be_zero
      end
      scheduler.shutdown

      expect(RUN_JOBS.size).to eq(number_of_jobs), lambda {
        job_counts = RUN_JOBS.tally
        duplicates = job_counts.select { |_, count| count > 1 }
        "Expected #{number_of_jobs} runs but got #{RUN_JOBS.size}. Duplicates: #{duplicates}"
      }
      expect(GoodJob::Job.finished.count).to eq number_of_jobs
    end

    it "#{strategy}: running job shows correct status (locked_by_id or advisory lock present)" do
      stub_const "BLOCKING_LATCH", Concurrent::CountDownLatch.new(1)
      stub_const 'BlockingJob', (Class.new(ActiveJob::Base) do
        def perform
          BLOCKING_LATCH.wait(5)
        end
      end)

      BlockingJob.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
      BlockingJob.perform_later

      performer = GoodJob::JobPerformer.new('*')
      scheduler = GoodJob::Scheduler.new(performer, max_threads: 1)
      scheduler.create_thread

      wait_until(max: 5, increments_of: 0.1) do
        expect(GoodJob::Job.last.performed_at).to be_present
      end

      job = GoodJob::Job.last
      expect(job.reload).to be_running

      BLOCKING_LATCH.count_down
      wait_until(max: 5, increments_of: 0.1) { expect(GoodJob::Job.last.finished_at).to be_present }
      scheduler.shutdown
    end
  end

  it_behaves_like 'a lock strategy that executes jobs correctly', :advisory
  it_behaves_like 'a lock strategy that executes jobs correctly', :skiplocked
  it_behaves_like 'a lock strategy that executes jobs correctly', :hybrid

  describe 'mixed-mode coexistence (rolling deploy)' do
    it 'does not double-execute jobs when advisory and skiplocked workers run concurrently' do
      number_of_jobs = 20

      GoodJob::Job.logger.silence do
        jobs = Array.new(number_of_jobs) { TestJob.new }
        TestJob.queue_adapter.enqueue_all(jobs)
      end

      # Worker 1: advisory strategy
      GoodJob.configuration.options[:lock_strategy] = :advisory
      advisory_performer = GoodJob::JobPerformer.new('*')
      advisory_scheduler = GoodJob::Scheduler.new(advisory_performer, max_threads: 3)
      3.times { advisory_scheduler.create_thread }

      # Worker 2: skiplocked strategy
      GoodJob.configuration.options[:lock_strategy] = :skiplocked
      skiplocked_performer = GoodJob::JobPerformer.new('*')
      skiplocked_scheduler = GoodJob::Scheduler.new(skiplocked_performer, max_threads: 3)
      3.times { skiplocked_scheduler.create_thread }

      wait_until(max: 30, increments_of: 0.2) do
        expect(GoodJob::Job.unfinished.count).to be_zero
      end

      advisory_scheduler.shutdown
      skiplocked_scheduler.shutdown

      expect(RUN_JOBS.size).to eq(number_of_jobs), lambda {
        job_counts = RUN_JOBS.tally
        duplicates = job_counts.select { |_, count| count > 1 }
        "Expected #{number_of_jobs} unique executions but got #{RUN_JOBS.size}. Duplicates: #{duplicates}"
      }
    end

    it 'does not double-execute jobs when skiplocked and hybrid workers run concurrently' do
      number_of_jobs = 20

      GoodJob::Job.logger.silence do
        jobs = Array.new(number_of_jobs) { TestJob.new }
        TestJob.queue_adapter.enqueue_all(jobs)
      end

      GoodJob.configuration.options[:lock_strategy] = :skiplocked
      skiplocked_performer = GoodJob::JobPerformer.new('*')
      skiplocked_scheduler = GoodJob::Scheduler.new(skiplocked_performer, max_threads: 3)
      3.times { skiplocked_scheduler.create_thread }

      GoodJob.configuration.options[:lock_strategy] = :hybrid
      hybrid_performer = GoodJob::JobPerformer.new('*')
      hybrid_scheduler = GoodJob::Scheduler.new(hybrid_performer, max_threads: 3)
      3.times { hybrid_scheduler.create_thread }

      wait_until(max: 30, increments_of: 0.2) do
        expect(GoodJob::Job.unfinished.count).to be_zero
      end

      skiplocked_scheduler.shutdown
      hybrid_scheduler.shutdown

      expect(RUN_JOBS.size).to eq(number_of_jobs), lambda {
        job_counts = RUN_JOBS.tally
        duplicates = job_counts.select { |_, count| count > 1 }
        "Expected #{number_of_jobs} unique executions but got #{RUN_JOBS.size}. Duplicates: #{duplicates}"
      }
    end
  end
end
