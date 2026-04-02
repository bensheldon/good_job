# frozen_string_literal: true

require 'rails_helper'

describe GoodJob::CronEntriesController do
  def count_queries(&block)
    count = 0
    counter = ->(*_args) { count += 1 }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end

  around do |example|
    orig_value = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.call
    ActionController::Base.allow_forgery_protection = orig_value
  end

  describe 'GET #index' do
    before do
      ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
    end

    it 'renders with a bounded number of queries regardless of cron entry count' do
      # Stub multiple cron entries to exercise scaling behavior
      extra_entries = 10.times.map do |i|
        GoodJob::CronEntry.new(key: :"test_cron_#{i}", cron: "* * * * *", class: "ExampleJob")
      end
      all_entries = GoodJob::CronEntry.all + extra_entries
      allow(GoodJob::CronEntry).to receive(:all).and_return(all_entries)

      all_entries.first(3).each { |entry| entry.enqueue(Time.current) }

      # Warm framework/schema caches
      get good_job.cron_entries_path

      query_count = count_queries { get good_job.cron_entries_path }

      expect(response).to have_http_status(:ok)
      # Query count should be fixed (last_jobs + enabled/disabled settings),
      # not scale with the number of cron entries.
      expect(query_count).to be <= 10
    end
  end

  describe 'PUT #disable' do
    it 'disables cron' do
      cron_entry = GoodJob::CronEntry.find(:example)
      expect do
        put good_job.disable_cron_entry_path(cron_key: 'example')
      end.to change { cron_entry.enabled? }.from(true).to(false)
      expect(response).to have_http_status(:see_other)
    end
  end

  describe 'PUT #enable' do
    it 'disables cron' do
      cron_entry = GoodJob::CronEntry.find(:example)
      cron_entry.disable
      expect do
        put good_job.enable_cron_entry_path(cron_key: 'example')
      end.to change { cron_entry.enabled? }.from(false).to(true)
      expect(response).to have_http_status(:see_other)
    end
  end

  describe 'POST #enqueue' do
    before do
      allow(ExampleJob).to receive(:queue_adapter).and_return(GoodJob::Adapter.new(execution_mode: :external))
    end

    it 'enqueues a job' do
      expect do
        post good_job.enqueue_cron_entry_path(cron_key: 'example')
      end.to change(GoodJob::Job, :count).by(1)
      expect(response).to have_http_status(:see_other)
    end

    it 'uses the application I18n.default_locale' do
      original_locale = I18n.default_locale
      I18n.default_locale = :de

      post good_job.enqueue_cron_entry_path(cron_key: 'example')
      expect(GoodJob::Job.last.serialized_params).to include("locale" => "de")
    ensure
      I18n.default_locale = original_locale
    end
  end
end
