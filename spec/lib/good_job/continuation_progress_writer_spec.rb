# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::ContinuationProgressWriter do
  subject(:progress_writer) { described_class.new(job) }

  let(:clock) { [1_000.0] }
  let(:lock_id) { SecureRandom.uuid }
  let(:active_job) { ContinuableJob.new("an argument") }
  let(:job) do
    active_job.queue_adapter.enqueue(active_job)
    GoodJob::Job.find(active_job.provider_job_id).tap do |job|
      job.update!(performed_at: Time.current, locked_by_id: lock_id, locked_at: Time.current, executions_count: 1)
    end
  end

  before do
    skip "ActiveJob::Continuable is not available in this Rails version" unless defined?(ActiveJob::Continuable)

    allow(GoodJob.configuration).to receive(:continuation_progress_interval).and_return(5.0)
    allow_any_instance_of(GoodJob::ThrottledBlock).to receive(:monotonic_now) { clock.first }
    stub_const "ContinuableJob", (Class.new(ActiveJob::Base) do
      include ActiveJob::Continuable

      def perform(*)
      end
    end)
    ContinuableJob.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)

    job
    progress_writer
    active_job.continuation = ActiveJob::Continuation.new(active_job, { "completed" => ["first"], "current" => ["second", 42] })
  end

  def advance(seconds)
    clock[0] += seconds
  end

  def persisted_params
    job.class.find(job.id).serialized_params
  end

  it 'does not write until the interval has elapsed since the job started' do
    advance(4)
    expect(progress_writer.write_if_due(active_job)).to be_nil
    expect(persisted_params["continuation"]).to eq({ "completed" => [] })

    advance(2)
    expect(progress_writer.write_if_due(active_job)).to be true
    expect(persisted_params["continuation"]).to eq({ "completed" => ["first"], "current" => ["second", 42] })
  end

  it 'only merges continuation progress into the serialized params' do
    original_params = persisted_params
    active_job.executions = 99

    advance(6)
    progress_writer.write_if_due(active_job)

    expect(persisted_params.except("continuation", "resumptions", "attributes")).to eq original_params.except("continuation", "resumptions", "attributes")
    expect(persisted_params["executions"]).not_to eq 99
    expect(job.serialized_params["continuation"]).to eq persisted_params["continuation"]
    expect(job).not_to be_serialized_params_changed
  end

  it 'waits for another interval after writing' do
    advance(6)
    progress_writer.write_if_due(active_job)

    advance(4)
    expect(progress_writer.write_if_due(active_job)).to be_nil
    advance(2)
    expect(progress_writer.write_if_due(active_job)).to be true
  end

  it 'does not write within an open transaction' do
    advance(6)
    GoodJob::Job.transaction do
      expect(progress_writer.write_if_due(active_job)).to be false
    end
    expect(persisted_params["continuation"]).to eq({ "completed" => [] })

    advance(6)
    expect(progress_writer.write_if_due(active_job)).to be true
  end

  it 'does not write the progress of a different job' do
    other_job = ContinuableJob.new

    advance(6)
    expect(progress_writer.write_if_due(other_job)).to be_nil
  end

  it 'stops writing once the job has been taken over by another execution' do
    job.class.where(id: job.id).update_all(executions_count: 2) # rubocop:disable Rails/SkipsModelValidations

    advance(6)
    expect(progress_writer.write_if_due(active_job)).to be false
    expect(persisted_params["continuation"]).to eq({ "completed" => [] })

    job.class.where(id: job.id).update_all(executions_count: 1) # rubocop:disable Rails/SkipsModelValidations
    advance(60)
    expect(progress_writer.write_if_due(active_job)).to be_nil
  end

  it 'writes while the execution owns the job even if its process lock was released' do
    GoodJob::Job.release_process(lock_id)

    advance(6)
    expect(progress_writer.write_if_due(active_job)).to be true
  end

  it 'does not overwrite other serialized params changed since the job was loaded' do
    job.class.where(id: job.id).update_all(["serialized_params = serialized_params || ?::jsonb", { "good_job_labels" => ["changed"] }.to_json]) # rubocop:disable Rails/SkipsModelValidations

    advance(6)
    progress_writer.write_if_due(active_job)

    expect(persisted_params).to include("good_job_labels" => ["changed"], "continuation" => { "completed" => ["first"], "current" => ["second", 42] })
  end

  it 'instruments writes' do
    payloads = []
    callback = ->(event) { payloads << event.payload }

    ActiveSupport::Notifications.subscribed(callback, "continuation_progress.good_job") do
      advance(6)
      progress_writer.write_if_due(active_job)
    end

    expect(payloads).to contain_exactly(include(job: job, active_job: active_job, lost_ownership: false))
  end

  it 'does not write once the job has finished' do
    job.class.where(id: job.id).update_all(finished_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

    advance(6)
    expect(progress_writer.write_if_due(active_job)).to be false
  end

  it 'instruments serialization errors' do
    error = StandardError.new("boom")
    allow(active_job).to receive(:serialize).and_raise(error)
    allow(GoodJob).to receive(:_on_thread_error)
    payloads = []
    callback = ->(event) { payloads << event.payload }

    ActiveSupport::Notifications.subscribed(callback, "continuation_progress.good_job") do
      advance(6)
      expect(progress_writer.write_if_due(active_job)).to be false
    end

    expect(payloads).to contain_exactly(include(exception_object: error))
    expect(GoodJob).to have_received(:_on_thread_error).with(error)
  end

  it 'reports write errors without raising them' do
    error = StandardError.new("boom")
    allow(GoodJob::Job).to receive(:where).and_raise(error)
    allow(GoodJob).to receive(:_on_thread_error)

    advance(6)
    expect(progress_writer.write_if_due(active_job)).to be false
    expect(GoodJob).to have_received(:_on_thread_error).with(error)
  end

  it 'does not write when disabled globally' do
    allow(GoodJob.configuration).to receive(:continuation_progress_interval).and_return(nil)
    disabled_writer = described_class.new(job)

    advance(600)
    expect(disabled_writer.write_if_due(active_job)).to be_nil
  end
end
