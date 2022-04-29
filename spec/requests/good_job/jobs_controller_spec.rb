# frozen_string_literal: true
require 'rails_helper'

describe GoodJob::JobsController, type: :request do
  around do |example|
    orig_value = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.call
    ActionController::Base.allow_forgery_protection = orig_value
  end

  before do
    allow(GoodJob).to receive(:preserve_job_records).and_return(true)
    ExampleJob.enable_test_adapter(GoodJob::Adapter.new(execution_mode: :inline))
  end

  describe 'GET #index' do
    before do
      ExampleJob.perform_later
    end

    it 'returns http success' do
      get good_job.jobs_path
      expect(response).to have_http_status(:success)
    end
  end

  describe 'PUT #mass_update' do
    let!(:job) do
      ExampleJob.perform_later
      GoodJob::ActiveJobJob.first
    end

    describe 'invalid input' do
      it 'invalid job id returns success' do
        put good_job.mass_update_jobs_path, params: {
          job_ids: ["garbage"],
          mass_action: 'retry',
        }
        expect(response).to have_http_status(:found)
        expect(flash[:notice]).to eq('No jobs were retried')
      end

      it 'invalid mass_action returns 400' do
        put good_job.mass_update_jobs_path, params: {
          job_ids: [job.id],
          mass_action: 'garbage',
        }
        expect(response).to have_http_status(:bad_request)
      end
    end

    describe 'mass_action=discard' do
      before do
        job.update(finished_at: nil)
      end

      it 'discards jobs' do
        put good_job.mass_update_jobs_path, params: {
          mass_action: 'discard',
          job_ids: [job.id],
        }

        expect(response).to have_http_status(:found)
        expect(flash[:notice]).to eq('Successfully discarded 1 job')

        job.reload
        expect(job.finished_at).to be_present
        expect(job.error).to include "Discarded through dashboard"
      end
    end

    describe 'mass_action=reschedule' do
      before do
        job.update(finished_at: nil, scheduled_at: 1.day.from_now)
      end

      it 'reschedules jobs' do
        put good_job.mass_update_jobs_path, params: {
          mass_action: 'reschedule',
          job_ids: [job.id],
        }

        expect(response).to have_http_status(:found)
        expect(flash[:notice]).to eq('Successfully rescheduled 1 job')

        job.reload
        expect(job.scheduled_at).to be_within(1.second).of(Time.current)
      end
    end

    describe 'mass_action=retry' do
      before do
        job.update(error: "Error message")
      end

      it 'retries the job' do
        put good_job.mass_update_jobs_path, params: {
          mass_action: 'retry',
          job_ids: [job.id],
        }

        expect(response).to have_http_status(:found)
        expect(flash[:notice]).to eq('Successfully retried 1 job')

        job.reload
        expect(job.executions.count).to eq 2
      end
    end

    describe 'all_job_ids option' do
      before do
        job.update(finished_at: nil)
      end

      it 'performs the action on all the jobs' do
        put good_job.mass_update_jobs_path, params: {
          mass_action: 'discard',
          all_job_ids: 1,
        }

        expect(response).to have_http_status(:found)
        expect(flash[:notice]).to eq('Successfully discarded 1 job')

        job.reload
        expect(job.finished_at).to be_present
        expect(job.error).to include "Discarded through dashboard"
      end
    end
  end
end
