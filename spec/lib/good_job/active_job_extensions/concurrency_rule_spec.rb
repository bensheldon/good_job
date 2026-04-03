# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::ActiveJobExtensions::Concurrency do
  before do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
  end

  def stub_job_class(rule, class_name: 'TestJob')
    stub_const class_name, (Class.new(ActiveJob::Base) do
      include GoodJob::ActiveJobExtensions::Concurrency

      good_job_concurrency_rule(rule)

      def id
        job_id
      end

      def perform(name:)
      end
    end)
  end

  describe 'Labels module inclusion' do
    before { stub_job_class({}) }

    it 'includes the Labels module' do
      expect(TestJob.ancestors).to include(GoodJob::ActiveJobExtensions::Labels)
    end
  end

  describe '.good_job_concurrency_rule' do
    let(:test_rule) { { label: -> { arguments.first[:name] }, enqueue_limit: 1 } }

    before { stub_job_class(test_rule) }

    it 'stores rules on the class' do
      expect(TestJob.good_job_concurrency_rules).to be_an(Array)
      expect(TestJob.good_job_concurrency_rules.first).to be_a(GoodJob::ActiveJobExtensions::Concurrency::Rule)
    end
  end

  describe 'without labels' do
    let(:test_rule) { { enqueue_limit: 1 } }

    before do
      stub_job_class(test_rule)
      stub_job_class(test_rule, class_name: 'AnotherTestJob')
    end

    it 'enforces concurrency across job classes' do
      expect(TestJob.perform_later(name: "Alice")).to be_present
      expect(AnotherTestJob.perform_later(name: "Alice")).to be false
    end
  end

  describe 'label application and enqueue limits' do
    let(:test_rule) { { label: -> { arguments.first[:name] }, enqueue_limit: 1 } }

    before { stub_job_class(test_rule) }

    it 'applies label and enforces enqueue limit' do
      expect(TestJob.set(good_job_labels: ["Alice"]).perform_later(name: "Alice")).to be_present
      expect(TestJob.set(good_job_labels: ["Alice"]).perform_later(name: "Alice")).to be false

      job = GoodJob::Job.find_by(job_class: 'TestJob')
      expect(job.labels).to include("Alice")
    end
  end

  describe 'rule-based throttles and perform limits' do
    context 'with an enqueue throttle rule' do
      let(:test_rule) { { label: -> { arguments.first[:name] }, enqueue_throttle: [1, 1.minute] } }

      before { stub_job_class(test_rule) }

      it 'does not enqueue if throttle period has not passed' do
        expect(TestJob.set(good_job_labels: ["Alice"]).perform_later(name: "Alice")).to be_present
        expect(TestJob.set(good_job_labels: ["Alice"]).perform_later(name: "Alice")).to be false
        Timecop.travel(61.seconds.from_now) do
          expect(TestJob.set(good_job_labels: ["Alice"]).perform_later(name: "Alice")).to be_present
        end
      end
    end

    context 'with a perform limit rule' do
      let(:test_rule) { { label: -> { arguments.first[:name] }, perform_limit: 0 } }

      before do
        allow(GoodJob).to receive(:preserve_job_records).and_return(true)
        stub_job_class(test_rule)
      end

      it 'errors and retries jobs if concurrency is exceeded' do
        active_job = TestJob.set(good_job_labels: ["Alice"]).perform_later(name: "Alice")

        performer = GoodJob::JobPerformer.new('*')
        scheduler = GoodJob::Scheduler.new(performer, max_threads: 5)
        5.times { scheduler.create_thread }

        sleep_until(max: 10, increments_of: 0.5) do
          GoodJob::Execution.where(active_job_id: active_job.job_id).finished.count >= 1
        end
        scheduler.shutdown

        expect(GoodJob::Job.find_by(active_job_id: active_job.job_id).labels).to include("Alice")

        expect(GoodJob::Execution.count).to be >= 1
        expect(GoodJob::Execution.where("error LIKE '%GoodJob::ActiveJobExtensions::Concurrency::ConcurrencyExceededError%'")).to be_present
      end
    end

    context 'with a perform throttle rule' do
      let(:test_rule) { { label: "static", perform_throttle: [1, 1.minute] } }

      before do
        allow(GoodJob).to receive(:preserve_job_records).and_return(true)
        stub_job_class(test_rule)
      end

      it 'does not perform if throttle period has not passed' do
        TestJob.set(good_job_labels: ["static"]).perform_later(name: "Alice")
        TestJob.set(good_job_labels: ["static"]).perform_later(name: "Alice")
        TestJob.set(good_job_labels: ["static"]).perform_later(name: "Alice")
        GoodJob.perform_inline

        expect(GoodJob::Job.finished.count).to eq 1

        Timecop.travel(61.seconds)
        TestJob.set(good_job_labels: ["static"]).perform_later(name: "Alice")
        GoodJob.perform_inline

        expect(GoodJob::Job.finished.count).to eq 2

        Timecop.travel(61.seconds)
        GoodJob.perform_inline

        expect(GoodJob::Job.finished.count).to eq 3
      end
    end

    context 'with a multipart rule' do
      let(:test_rule) { { label: -> { arguments.first[:name] }, enqueue_throttle: [1, 1.minute], perform_limit: 0 } }

      before do
        allow(GoodJob).to receive(:preserve_job_records).and_return(true)
        stub_job_class(test_rule)
      end

      it 'enforces both enqueue throttle and perform limit' do
        job_1 = TestJob.set(good_job_labels: ["Alice"]).perform_later(name: "Alice")
        expect(job_1).to be_present
        job_2 = TestJob.set(good_job_labels: ["Alice"]).perform_later(name: "Alice")
        expect(job_2).to be false
        GoodJob.perform_inline

        Timecop.travel(61.seconds)
        job_3 = TestJob.set(good_job_labels: ["Alice"]).perform_later(name: "Alice")
        expect(job_3).to be_present
        GoodJob.perform_inline

        performer = GoodJob::JobPerformer.new('*')
        scheduler = GoodJob::Scheduler.new(performer, max_threads: 5)
        5.times { scheduler.create_thread }

        sleep_until(max: 10, increments_of: 0.5) do
          GoodJob::Execution.where(active_job_id: GoodJob::Job.last.id).finished.count >= 1
        end
        scheduler.shutdown

        expect(GoodJob::Execution.where("error LIKE '%GoodJob::ActiveJobExtensions::Concurrency::ConcurrencyExceededError%'")).to be_present

        expect(GoodJob::Job.finished.count).to eq 0
      end
    end
  end
end
