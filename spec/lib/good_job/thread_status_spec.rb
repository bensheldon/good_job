# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::ThreadStatus do
  describe ".current_thread_running?" do
    context "when called outside of an execution context" do
      it "returns true" do
        expect(GoodJob.current_thread_running?).to eq(true)
      end
    end
  end

  describe ".current_thread_shutting_down?" do
    context "when called outside of an execution context" do
      it "returns nil" do
        expect(GoodJob.current_thread_shutting_down?).to eq(nil)
      end
    end
  end

  context "when inside of an execution context" do
    let(:capsule) { GoodJob::Capsule.new }
    let(:adapter) { GoodJob::Adapter.new(execution_mode: :async_all, _capsule: capsule) }

    before do
      stub_const "JOB_RUNNING_EVENT", Concurrent::Event.new
      stub_const "START_SHUTDOWN_EVENT", Concurrent::Event.new
      stub_const "STATUSES", []
      stub_const "TestJob", (Class.new(ActiveJob::Base) do
        def perform
          STATUSES << GoodJob.current_thread_running?
          STATUSES << GoodJob.current_thread_shutting_down?
          JOB_RUNNING_EVENT.set
          START_SHUTDOWN_EVENT.wait(5)
          STATUSES << GoodJob.current_thread_running?
          STATUSES << GoodJob.current_thread_shutting_down?
        end
      end)

      TestJob.queue_adapter = adapter
    end

    after do
      capsule.shutdown
    end

    it "returns proper values" do
      TestJob.perform_later

      JOB_RUNNING_EVENT.wait(5)
      capsule.shutdown(timeout: nil) # don't wait for the shutdown to complete
      START_SHUTDOWN_EVENT.set
      capsule.shutdown

      expect(STATUSES).to eq([true, false, false, true])
    end
  end
end
