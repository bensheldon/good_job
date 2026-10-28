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

      wait_while_progressing(progress: -> { GoodJob::Job.finished.count }, increments_of: 0.2) do
        # Wake threads whose dequeue came up empty, as the Poller does in production
        5.times { scheduler.create_thread }
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
    # Each worker gets its own capsule so that it uses its own lock strategy, like separate processes would.
    def start_worker(lock_strategy)
      capsule = GoodJob::Capsule.new(configuration: GoodJob::Configuration.new({ lock_strategy: lock_strategy }))
      performer = GoodJob::JobPerformer.new('*', capsule: capsule)
      GoodJob::Scheduler.new(performer, max_threads: 3).tap do |scheduler|
        3.times { scheduler.create_thread }
      end
    end

    def expect_no_double_execution(*lock_strategies)
      number_of_jobs = 20
      GoodJob::Job.logger.silence do
        jobs = Array.new(number_of_jobs) { TestJob.new }
        TestJob.queue_adapter.enqueue_all(jobs)
      end

      %i[perform_with_advisory_lock perform_with_skip_locked perform_with_hybrid_lock].each do |method|
        allow(GoodJob::Job).to receive(method).and_call_original
      end

      schedulers = lock_strategies.map { |lock_strategy| start_worker(lock_strategy) }

      wait_while_progressing(progress: -> { GoodJob::Job.finished.count }, increments_of: 0.2) do
        # Wake threads whose dequeue came up empty, as the Poller does in production
        schedulers.each { |scheduler| 3.times { scheduler.create_thread } }
        expect(GoodJob::Job.unfinished.count).to be_zero
      end
      schedulers.each(&:shutdown)

      expect(RUN_JOBS.size).to eq(number_of_jobs), lambda {
        job_counts = RUN_JOBS.tally
        duplicates = job_counts.select { |_, count| count > 1 }
        "Expected #{number_of_jobs} unique executions but got #{RUN_JOBS.size}. Duplicates: #{duplicates}"
      }
    end

    # :advisory and :skiplocked workers cannot run together: neither sees the other's locks.
    it 'does not double-execute jobs when advisory and hybrid workers run concurrently' do
      expect_no_double_execution(:advisory, :hybrid)

      expect(GoodJob::Job).to have_received(:perform_with_advisory_lock).at_least(:once)
      expect(GoodJob::Job).to have_received(:perform_with_hybrid_lock).at_least(:once)
    end

    it 'does not double-execute jobs when skiplocked and hybrid workers run concurrently' do
      expect_no_double_execution(:skiplocked, :hybrid)

      expect(GoodJob::Job).to have_received(:perform_with_skip_locked).at_least(:once)
      expect(GoodJob::Job).to have_received(:perform_with_hybrid_lock).at_least(:once)
    end
  end

  describe 'perform_throttle with ordered queues' do
    before do
      allow(GoodJob.deprecator).to receive(:warn)
      stub_const 'ThrottledJob', (Class.new(ActiveJob::Base) do
        include GoodJob::ActiveJobExtensions::Concurrency

        good_job_control_concurrency_with(
          perform_throttle: -> { [10, 1.minute] },
          key: -> { 'shared-key' }
        )

        def perform
          RUN_JOBS << provider_job_id
        end
      end)
      ThrottledJob.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
    end

    shared_examples 'performs throttled jobs without error' do |strategy|
      it "#{strategy}: performs a throttled job dequeued by an ordered-queue worker" do
        GoodJob.configuration.options[:lock_strategy] = strategy

        ThrottledJob.set(queue: 'default').perform_later

        expect { GoodJob.perform_inline('+default,other') }.not_to raise_error

        job = GoodJob::Job.last
        expect(job.finished_at).to be_present
        expect(job.error).to be_nil
        expect(RUN_JOBS.size).to eq 1
      end
    end

    it_behaves_like 'performs throttled jobs without error', :advisory
    it_behaves_like 'performs throttled jobs without error', :skiplocked
    it_behaves_like 'performs throttled jobs without error', :hybrid
  end
end
