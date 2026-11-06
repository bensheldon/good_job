# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::ActiveJobExtensions::ContinuationProgress do
  let(:clock) { [1_000.0] }
  let(:active_job) { ContinuableJob.new }
  let(:progress_writer) do
    active_job.queue_adapter.enqueue(active_job)
    job = GoodJob::Job.find(active_job.provider_job_id)
    job.update!(performed_at: Time.current, executions_count: 1)
    GoodJob::ContinuationProgressWriter.new(job)
  end

  before do
    skip "ActiveJob::Continuable is not available in this Rails version" unless defined?(ActiveJob::Continuable)

    allow(GoodJob.configuration).to receive(:continuation_progress_interval).and_return(5.0)
    allow_any_instance_of(GoodJob::ThrottledBlock).to receive(:monotonic_now) { clock.first }
    stub_const "ContinuableJob", (Class.new(ActiveJob::Base) do
      include ActiveJob::Continuable
      include GoodJob::ActiveJobExtensions::ContinuationProgress

      def perform(*)
      end
    end)
    ContinuableJob.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
  end

  def advance(seconds)
    clock[0] += seconds
  end

  it 'uses the global interval when not set' do
    progress_writer

    advance(6)
    expect(progress_writer.write_if_due(active_job)).to be true
  end

  it 'uses the job class interval' do
    ContinuableJob.good_job_continuation_progress_interval = 30.seconds
    progress_writer

    advance(20)
    expect(progress_writer.write_if_due(active_job)).to be_nil
    advance(20)
    expect(progress_writer.write_if_due(active_job)).to be true
  end

  it 'uses the global interval when set to nil' do
    ContinuableJob.good_job_continuation_progress_interval = nil
    progress_writer

    advance(6)
    expect(progress_writer.write_if_due(active_job)).to be true
  end

  [false, 0].each do |value|
    it "disables periodic writes with #{value.inspect}" do
      ContinuableJob.good_job_continuation_progress_interval = value
      progress_writer

      advance(600)
      expect(progress_writer.write_if_due(active_job)).to be_nil
    end
  end

  it 'is inherited by subclasses' do
    ContinuableJob.good_job_continuation_progress_interval = false

    expect(Class.new(ContinuableJob).good_job_continuation_progress_interval).to be false
  end
end
