# frozen_string_literal: true
require 'rails_helper'

describe 'Live Poll', type: :system, js: true do
  before do
    allow(GoodJob).to receive(:retry_on_unhandled_error).and_return(false)
    allow(GoodJob).to receive(:preserve_job_records).and_return(true)
  end

  it 'reloads the dashboard when active' do
    # Load the page with live poll enabled
    visit 'good_job?poll=1'
    expect(page).to have_checked_field('toggle-poll')

    # Verify that the page reloads
    last_updated = page.find('#page-updated-at')['datetime']
    wait_until do
      expect(last_updated).not_to eq(page.find('#page-updated-at')['datetime'])
    end

    # Disable live polling and verify that the page does not reload
    uncheck('toggle-poll')
    last_updated = page.find('#page-updated-at')['datetime']
    sleep 2
    expect(last_updated).to eq(page.find('#page-updated-at')['datetime'])

    # Re-enable live polling and verify it is reloading again
    check('toggle-poll')
    last_updated = page.find('#page-updated-at')['datetime']
    wait_until do
      expect(last_updated).not_to eq(page.find('#page-updated-at')['datetime'])
    end
  end
end
