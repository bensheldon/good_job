# frozen_string_literal: true
require 'rails_helper'

describe ExampleJob do
  before do
    allow(GoodJob).to receive(:preserve_job_records).and_return(true)
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :inline)
  end

  describe "#perform" do
    describe "SUCCESS_TYPE" do
      it 'completes successfully' do
        active_job = described_class.perform_later(described_class::SUCCESS_TYPE)
        execution = GoodJob::Execution.find(active_job.provider_job_id)
        expect(execution.error).to be_nil
      end
    end

    describe "ERROR_ONCE_TYPE" do
      it 'errors once then succeeds' do
        active_job = described_class.perform_later(described_class::ERROR_ONCE_TYPE)
        10.times do
          GoodJob.perform_inline
          travel(5.minutes)
        end
        travel_back

        executions = GoodJob::Execution.where(active_job_id: active_job.job_id).order(created_at: :asc)
        expect(executions.size).to eq 2
        expect(executions.last.error).to be_nil
      end
    end

    describe "ERROR_FIVE_TIMES_TYPE" do
      it 'errors five times then succeeds' do
        active_job = described_class.perform_later(described_class::ERROR_FIVE_TIMES_TYPE)
        10.times do
          GoodJob.perform_inline
          travel(5.minutes)
        end
        travel_back

        executions = GoodJob::Execution.where(active_job_id: active_job.job_id).order(created_at: :asc)
        expect(executions.size).to eq 6
        expect(executions.last.error).to be_nil
      end
    end

    describe "DEAD_TYPE" do
      it 'errors but does not retry' do
        described_class.perform_later(described_class::DEAD_TYPE)
        10.times do
          GoodJob.perform_inline
          travel(5.minutes)
        end
        travel_back

        active_job_id = GoodJob::Execution.last.active_job_id

        executions = GoodJob::Execution.where(active_job_id: active_job_id).order(created_at: :asc)
        expect(executions.size).to eq 3
        expect(executions.last.error).to be_present
      end
    end

    describe "SLOW_TYPE" do
      it 'sleeps for period' do
        expect_any_instance_of(Object).to receive(:sleep)

        active_job = described_class.perform_later(described_class::SLOW_TYPE)

        execution = GoodJob::Execution.find(active_job.provider_job_id)
        expect(execution.error).to be_nil
      end
    end
  end
end
