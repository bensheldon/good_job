# frozen_string_literal: true
require 'rails_helper'

describe 'Cron Schedules', type: :system do
  before do
    allow(GoodJob).to receive(:retry_on_unhandled_error).and_return(false)
    allow(GoodJob).to receive(:preserve_job_records).and_return(true)
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
  end

  it 'renders successfully' do
    cron_entry = GoodJob::CronEntry.find(:example)

    visit '/good_job/cron_entries'
    expect(page).to have_content cron_entry.job_class
    expect(cron_entry.last_at).to be_nil

    within "##{dom_id(cron_entry)}" do
      click_on "Run cron entry now"
    end

    click_on "Job #{cron_entry.last_job.id}"
    expect(page).to have_content cron_entry.last_job.id
  end
end
