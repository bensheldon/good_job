# frozen_string_literal: true

require 'rails_helper'

describe GoodJob::MetricsController do
  describe 'GET #primary_nav' do
    it 'returns the primary navigation metrics' do
      get good_job.metrics_primary_nav_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(
        {
          jobs_count: '0',
          batches_count: '0',
          cron_entries_count: '1',
          processes_count: '0',
        }.to_json
      )
    end
  end

  describe 'GET #job_status' do
    it 'returns the primary navigation metrics' do
      get good_job.metrics_job_status_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(
        {
          "scheduled" => "0",
          "retried" => "0",
          "queued" => "0",
          "running" => "0",
          "succeeded" => "0",
          "discarded" => "0",
        }.to_json
      )
    end
  end
end
