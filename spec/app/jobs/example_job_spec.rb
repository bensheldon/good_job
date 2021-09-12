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
        good_job = GoodJob::Job.find(active_job.provider_job_id)
        expect(good_job.error).to be_nil
      end
    end

    describe ":error_once" do
      it 'errors once then succeeds' do
        active_job = described_class.perform_later('error_once')
        good_jobs = GoodJob::Job.where(active_job_id: active_job.job_id).order(created_at: :asc)
        expect(good_jobs.size).to eq 2
        expect(good_jobs.last.error).to be_nil
      end
    end

    describe ":error_five_times" do
      it 'errors five times then succeeds' do
        active_job = described_class.perform_later('error_five_times')
        good_jobs = GoodJob::Job.where(active_job_id: active_job.job_id).order(created_at: :asc)
        expect(good_jobs.size).to eq 6
        expect(good_jobs.last.error).to be_nil
      end
    end

    describe ":dead" do
      it 'errors but does not retry' do
        active_job = described_class.perform_later('dead')
        good_jobs = GoodJob::Job.where(active_job_id: active_job.job_id).order(created_at: :asc)
        expect(good_jobs.size).to eq 3
        expect(good_jobs.last.error).to be_present
      end
    end
  end
end
