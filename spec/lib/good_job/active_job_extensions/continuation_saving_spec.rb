# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::ActiveJobExtensions::ContinuationSaving do
  let(:clock) { [1_000.0] }
  let(:saved_cursors) { [] }
  let(:adapter) { ActiveJob::QueueAdapters::TestAdapter.new }
  let(:active_job) { ContinuableJob.new }
  let(:good_job_record) { instance_double(GoodJob::Job, active_job_id: active_job.job_id) }

  before do
    skip "ActiveJob::Continuable is not available in this Rails version" unless defined?(ActiveJob::Continuable)

    clock = self.clock
    saved_cursors = self.saved_cursors
    stub_const "ContinuableJob", (Class.new(ActiveJob::Base) do
      include ActiveJob::Continuable
      include GoodJob::ActiveJobExtensions::ContinuationSaving

      # Each item takes 2 seconds
      define_method(:perform) do |items = 10|
        step :process, start: 0 do |step|
          (step.cursor...items).each do
            clock[0] += 2
            step.advance!
          end
        end
      end
    end)
    ContinuableJob.queue_adapter = adapter

    throttled_block_class = described_class.const_get(:ThrottledBlock)
    allow_any_instance_of(throttled_block_class).to receive(:monotonic_now) { clock.first }
    allow(adapter).to receive(:stopping?).and_return(false)
    allow(good_job_record).to receive(:update_serialized_params) do |params|
      saved_cursors << params.dig("continuation", "current", 1)
      true
    end
    allow(GoodJob::CurrentThread).to receive(:job).and_return(good_job_record)
  end

  it 'saves the progress at checkpoints once the interval has elapsed since the job started or was last saved' do
    active_job.perform_now

    # Checkpoints happen every 2 seconds; the default interval is 5 seconds (plus up to 15% jitter)
    expect(saved_cursors).to eq [3, 6, 9]
  end

  it 'only saves the continuation progress' do
    active_job.perform_now

    expect(good_job_record).to have_received(:update_serialized_params).with(satisfy { |params| params.keys.difference(%w[continuation resumptions attributes]).empty? }).at_least(:once)
  end

  it 'uses the job class interval' do
    ContinuableJob.good_job_continuation_save_interval = 3.seconds
    active_job.perform_now

    # Due 3 to 3.45 seconds after starting or saving: every other checkpoint
    expect(saved_cursors).to eq [2, 4, 6, 8, 10]
  end

  [false, 0].each do |value|
    it "does not save with an interval of #{value.inspect}" do
      ContinuableJob.good_job_continuation_save_interval = value
      active_job.perform_now

      expect(good_job_record).not_to have_received(:update_serialized_params)
    end
  end

  it 'stops saving once a save fails' do
    allow(good_job_record).to receive(:update_serialized_params).and_return(false)
    active_job.perform_now

    expect(good_job_record).to have_received(:update_serialized_params).once
  end

  it 'reports errors and stops saving without raising them' do
    error = StandardError.new("boom")
    allow(good_job_record).to receive(:update_serialized_params).and_raise(error)
    allow(GoodJob).to receive(:_on_thread_error)

    expect { active_job.perform_now }.not_to raise_error
    expect(GoodJob).to have_received(:_on_thread_error).with(error).once
  end

  it 'does not save when the job is not being performed by GoodJob' do
    allow(GoodJob::CurrentThread).to receive(:job).and_return(nil)

    expect { active_job.perform_now }.not_to raise_error
  end

  it 'does not save the progress of a different job' do
    allow(good_job_record).to receive(:active_job_id).and_return(SecureRandom.uuid)
    active_job.perform_now

    expect(good_job_record).not_to have_received(:update_serialized_params)
  end

  it 'does not save when the job is stopping' do
    allow(adapter).to receive(:stopping?).and_return(true)
    ContinuableJob.good_job_continuation_save_interval = 1 # due at the first checkpoint
    active_job.perform_now

    expect(good_job_record).not_to have_received(:update_serialized_params)
  end

  it 'does not save from a checkpoint inside a database transaction' do
    skip "Active Record does not check checkpoints for open transactions in this Rails version" unless defined?(ActiveRecord::Railties::JobCheckpoints)

    ActiveRecord::Base.transaction do
      expect { active_job.perform_now }.to raise_error(ActiveJob::Continuation::CheckpointError)
    end
    expect(good_job_record).not_to have_received(:update_serialized_params)
  end

  it 'saves regardless of the order the modules were included in' do
    clock = self.clock
    job_class = Class.new(ActiveJob::Base) do
      include GoodJob::ActiveJobExtensions::ContinuationSaving
      include ActiveJob::Continuable

      define_method(:perform) do
        step :process, start: 0 do |step|
          (step.cursor...3).each do
            clock[0] += 3
            step.advance!
          end
        end
      end
    end
    job_class.queue_adapter = adapter
    job = job_class.new
    allow(good_job_record).to receive(:active_job_id).and_return(job.job_id)
    job.perform_now

    expect(saved_cursors).to eq [2]
  end

  it 'is inherited by subclasses' do
    ContinuableJob.good_job_continuation_save_interval = false

    expect(Class.new(ContinuableJob).good_job_continuation_save_interval).to be false
  end
end
