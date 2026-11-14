# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Continuation progress' do
  let(:clock) { [1_000.0] }
  let(:events) { [] }
  let(:resumed_with) { [] }
  let(:continuable_job) do
    clock = self.clock
    events = self.events
    resumed_with = self.resumed_with

    stub_const('CheckpointedJob', Class.new(ActiveJob::Base) do
      include ActiveJob::Continuable
      include GoodJob::ActiveJobExtensions::ContinuationSaving

      self.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
      self.resume_errors_after_advancing = false

      # Active Job attributes are saved with the progress in Rails 8.2+
      if respond_to?(:attribute)
        attribute :processed_count, :integer, default: 0
      else
        attr_writer :processed_count

        def processed_count = @processed_count || 0
      end

      class << self
        attr_accessor :crash_at
      end

      define_method(:perform) do
        step :process, start: 0 do |step|
          resumed_with << { resumptions: resumptions, processed_count: processed_count } if step.resumed?
          (step.cursor...5).each do |item|
            events << item
            clock[0] += 2 # each item takes 2 seconds
            raise "crash" if item == self.class.crash_at

            self.processed_count += 1
            step.advance!
          end
        end
      end
    end)
  end

  before do
    skip "ActiveJob::Continuable is not available in this Rails version" unless defined?(ActiveJob::Continuable)

    allow_any_instance_of(GoodJob::ActiveJobExtensions::ContinuationSaving.const_get(:ThrottledBlock)).to receive(:monotonic_now) { clock.first }
  end

  it 'resumes from the last periodically saved progress after a non-graceful interruption' do
    continuable_job.crash_at = 3
    continuable_job.perform_later
    expect { GoodJob.perform_inline }.to raise_error(RuntimeError, "crash")

    job = GoodJob::Job.find_by(job_class: "CheckpointedJob")
    expect(events).to eq [0, 1, 2, 3]
    # The checkpoint is due after item 2 (6 seconds), but not after item 1 (4 seconds)
    expect(job.serialized_params.dig("continuation", "current")).to eq ["process", 3]
    expect(job.serialized_params.dig("attributes", "processed_count")).to eq 3 if continuable_job.respond_to?(:attribute)
    expect(job.serialized_params["resumptions"]).to eq 0
    expect(job.serialized_params["executions"]).to eq 0

    # Simulate the process having been killed while performing the job
    job.update!(finished_at: nil, error: nil, error_event: nil, performed_at: 1.minute.ago, locked_by_id: nil, locked_at: nil)
    continuable_job.crash_at = nil
    GoodJob.perform_inline

    expect(events).to eq [0, 1, 2, 3, 3, 4]
    expect(resumed_with).to eq [{ resumptions: 1, processed_count: continuable_job.respond_to?(:attribute) ? 3 : 0 }]
    expect(job.reload).to have_attributes(finished_at: be_present, error: nil)
  end
end
