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
          cron_entries_count: GoodJob::CronEntry.all.size.to_s,
          cron_entries_enabled_count: '0',
          cron_entries_paused_count: GoodJob::CronEntry.all.size.to_s,
          pauses_count: '0',
          processes_count: '0',
          discarded_count: '0',
        }.to_json
      )
    end

    it 'counts cron entries enabled or disabled through settings' do
      cron_entries = [
        GoodJob::CronEntry.new(key: :on_by_default, cron: "* * * * *", class: "ExampleJob"),
        GoodJob::CronEntry.new(key: :on_by_default_then_disabled, cron: "* * * * *", class: "ExampleJob"),
        GoodJob::CronEntry.new(key: :off_by_default, cron: "* * * * *", class: "ExampleJob", enabled_by_default: false),
        GoodJob::CronEntry.new(key: :off_by_default_then_enabled, cron: "* * * * *", class: "ExampleJob", enabled_by_default: false),
      ]
      allow(GoodJob::CronEntry).to receive(:all).and_return(cron_entries)
      GoodJob::Setting.cron_key_disable(:on_by_default_then_disabled)
      GoodJob::Setting.cron_key_enable(:off_by_default_then_enabled)

      get good_job.metrics_primary_nav_path

      expect(response.parsed_body).to include(
        'cron_entries_count' => '4',
        'cron_entries_enabled_count' => '2',
        'cron_entries_paused_count' => '2'
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
