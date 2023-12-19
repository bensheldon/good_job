# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::ActiveJobExtensions::Labels do
  before do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)

    stub_const 'TestJob', (Class.new(ActiveJob::Base) do
      include GoodJob::ActiveJobExtensions::Labels

      def perform
      end
    end)
  end

  it "is an empty array by default to Active Job, but null on the record" do
    expect(TestJob.good_job_labels).to eq []
    TestJob.perform_later

    job = GoodJob::Job.last
    expect(job.labels).to eq nil
    expect(job.active_job.good_job_labels).to eq []
  end

  it "is serialized and deserialized" do
    TestJob.good_job_labels = %w[buffalo gopher]

    expect(TestJob.good_job_labels).to eq %w[buffalo gopher]
    TestJob.perform_later

    job = GoodJob::Job.last
    expect(job.labels).to eq %w[buffalo gopher]
    expect(job.active_job.good_job_labels).to eq %w[buffalo gopher]
  end

  it "doesn't leak into the serialized params" do
    TestJob.good_job_labels = %w[buffalo gopher]
    TestJob.perform_later

    expect(GoodJob::Job.last.serialized_params).not_to have_key("good_job_labels")
  end

  it 'appropriately deserializes a nil value even when the class value is set' do
    TestJob.good_job_labels = ["buffalo"]

    TestJob.set(good_job_labels: []).perform_later

    job = GoodJob::Job.last
    expect(job.labels).to eq nil

    active_job = job.active_job
    expect(active_job.good_job_labels).to eq []
  end

  it 'is unique' do
    TestJob.good_job_labels = %w[buffalo gopher gopher]
    TestJob.perform_later

    job = GoodJob::Job.last
    expect(job.labels).to eq %w[buffalo gopher]

    active_job = job.active_job
    expect(active_job.good_job_labels).to eq %w[buffalo gopher]
  end

  it 'strips values' do
    TestJob.good_job_labels = ["buffalo", "    gopher    ", "gopher"]
    TestJob.perform_later

    active_job = GoodJob::Job.last.active_job
    expect(active_job.good_job_labels).to eq %w[buffalo gopher]
  end

  it "can contain non-string values" do
    TestJob.good_job_labels = ["buffalo", "key:value", 1, true, nil]
    TestJob.perform_later

    active_job = GoodJob::Job.last.active_job
    expect(active_job.good_job_labels).to eq ["buffalo", "key:value", "1", "true"]
  end

  context 'when a job is retried' do
    before do
      stub_const 'ExpectedError', Class.new(StandardError)
      stub_const 'TestJob', (Class.new(ActiveJob::Base) do
        include GoodJob::ActiveJobExtensions::Labels
        retry_on ExpectedError, wait: 0, attempts: 3

        def perform
          good_job_labels << "gopher"
          raise ExpectedError if executions < 3
        end
      end)
    end

    it 'retains the label when retried' do
      TestJob.set(good_job_labels: ["buffalo"]).perform_later
      GoodJob.perform_inline

      expect(GoodJob::DiscreteExecution.count).to eq 3
      expect(GoodJob::Job.first).to have_attributes(labels: %w[buffalo gopher])
    end
  end
end
