# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::ActiveJobExtensions::Concurrency do
  before do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
  end

  def stub_job_class(rule)
    stub_const 'TestJob', (Class.new(ActiveJob::Base) do
      include GoodJob::ActiveJobExtensions::Concurrency
      include GoodJob::ActiveJobExtensions::Labels

      good_job_concurrency_rule(rule)

      def perform(name:)
      end
    end)
  end

  describe '.good_job_concurrency_rule' do
    let(:test_rule) { { label: -> { arguments.first[:name] }, stage: :enqueue, limit: 1 } }

    before { stub_job_class(test_rule) }

    it 'stores rules on the class' do
      expect(TestJob.good_job_concurrency_rules).to be_an(Array)
      expect(TestJob.good_job_concurrency_rules.first).to include(:label, :stage, :limit)
    end
  end

  describe 'label application and enqueue limits' do
    let(:test_rule) { { label: -> { arguments.first[:name] }, stage: :enqueue, limit: 1 } }

    before { stub_job_class(test_rule) }

    it 'applies label and enforces enqueue limit' do
      expect(TestJob.perform_later(name: "Alice")).to be_present
      expect(TestJob.perform_later(name: "Alice")).to be false

      job = GoodJob::Job.find_by(job_class: 'TestJob')
      expect(job.labels).to include("concurrency:enqueue:limit:Alice")
    end
  end

  describe 'rule-based throttles and perform limits' do
    context 'with an enqueue throttle rule' do
      let(:test_rule) { { label: -> { arguments.first[:name] }, stage: :enqueue, throttle: [1, 1.minute] } }

      before { stub_job_class(test_rule) }

      it 'does not enqueue if throttle period has not passed' do
        expect(TestJob.perform_later(name: "Alice")).to be_present
        expect(TestJob.perform_later(name: "Alice")).to be false
        Timecop.travel(61.seconds.from_now) do
          expect(TestJob.perform_later(name: "Alice")).to be_present
        end
      end
    end

    context 'with a perform limit rule' do
      let(:test_rule) { { label: -> { arguments.first[:name] }, stage: :perform, limit: 0 } }

      before do
        allow(GoodJob).to receive(:preserve_job_records).and_return(true)
        stub_job_class(test_rule)
      end

      it 'errors and retries jobs if concurrency is exceeded' do
        active_job = TestJob.perform_later(name: "Alice")

        performer = GoodJob::JobPerformer.new('*')
        scheduler = GoodJob::Scheduler.new(performer, max_threads: 5)
        5.times { scheduler.create_thread }

        sleep_until(max: 10, increments_of: 0.5) do
          GoodJob::Execution.where(active_job_id: active_job.job_id).finished.count >= 1
        end
        scheduler.shutdown

        expect(GoodJob::Job.find_by(active_job_id: active_job.job_id).labels).to include("concurrency:perform:limit:Alice")

        expect(GoodJob::Execution.count).to be >= 1
        expect(GoodJob::Execution.where("error LIKE '%GoodJob::ActiveJobExtensions::Concurrency::ConcurrencyExceededError%'")).to be_present
      end
    end

    context 'with a perform throttle rule' do
      let(:test_rule) { { label: "static", stage: :perform, throttle: [1, 1.minute] } }

      before do
        allow(GoodJob).to receive(:preserve_job_records).and_return(true)
        stub_job_class(test_rule)
      end

      it 'does not perform if throttle period has not passed' do
        TestJob.perform_later(name: "Alice")
        TestJob.perform_later(name: "Alice")
        TestJob.perform_later(name: "Alice")
        GoodJob.perform_inline

        expect(GoodJob::Job.finished.count).to eq 1

        Timecop.travel(61.seconds)
        TestJob.perform_later(name: "Alice")
        GoodJob.perform_inline

        expect(GoodJob::Job.finished.count).to eq 2

        Timecop.travel(61.seconds)
        GoodJob.perform_inline

        expect(GoodJob::Job.finished.count).to eq 3
      end
    end
  end
end
