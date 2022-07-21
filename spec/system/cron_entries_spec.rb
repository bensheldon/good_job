# frozen_string_literal: true
require 'rails_helper'

describe 'Cron Schedules', type: :system do
  let(:cron_entry) { GoodJob::CronEntry.find(:example) }

  before do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
  end

  it 'can enqueue a cron_entry immediately' do
    visit '/good_job/cron_entries'
    expect(page).to have_content cron_entry.job_class
    expect(cron_entry.last_at).to be_nil

    within "##{dom_id(cron_entry)}" do
      accept_confirm { click_on "Enqueue cron entry now" }
    end

    wait_until do
      expect(cron_entry.last_job).to be_present
    end

    click_on "Job #{cron_entry.last_job.id}"
    expect(page).to have_content cron_entry.last_job.id
  end

  it 'can be enabled and disabled' do
    visit '/good_job/cron_entries'

    within "##{dom_id(cron_entry)}" do
      accept_confirm { click_on "Disable cron entry" }
    end
    expect(cron_entry.enabled?).to be false

    within "##{dom_id(cron_entry)}" do
      accept_confirm { click_on "Enable cron entry" }
    end

    expect(cron_entry.enabled?).to be true
  end
end
