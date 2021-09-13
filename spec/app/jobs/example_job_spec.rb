# frozen_string_literal: true
require 'rails_helper'

describe ExampleJob do
  before do
    allow(GoodJob).to receive(:preserve_job_records).and_return(true)
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :inline)
  end

  describe "#perform" do
    describe ":success" do
      it 'completes successfully' do
        active_job = described_class.perform_later('success')
        execution = GoodJob::Execution.find(active_job.provider_job_id)
        expect(execution.error).to be_nil
      end
    end

    describe ":error_once" do
      it 'errors once then succeeds' do
        active_job = described_class.perform_later('error_once')
        executions = GoodJob::Execution.where(active_job_id: active_job.job_id).order(created_at: :asc)
        expect(executions.size).to eq 2
        expect(executions.last.error).to be_nil
      end
    end

    describe ":error_five_times" do
      it 'errors five times then succeeds' do
        active_job = described_class.perform_later('error_five_times')
        executions = GoodJob::Execution.where(active_job_id: active_job.job_id).order(created_at: :asc)
        expect(executions.size).to eq 6
        expect(executions.last.error).to be_nil
      end
    end

    describe ":dead" do
      it 'errors but does not retry' do
        active_job = described_class.perform_later('dead')
        executions = GoodJob::Execution.where(active_job_id: active_job.job_id).order(created_at: :asc)
        expect(executions.size).to eq 3
        expect(executions.last.error).to be_present
      end
    end
  end
end
