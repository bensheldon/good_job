# frozen_string_literal: true

require 'rails_helper'

describe 'Content Security Policy', :js do
  it 'loads the dashboard without CSP violations' do
    log_entries = []
    browser_page = page.driver.browser.page
    browser_page.command("Log.enable")
    browser_page.on("Log.entryAdded") { |params| log_entries << params.dig("entry", "text") }

    visit good_job.jobs_path
    expect(page).to have_text "Jobs"
    # es-module-shims feature detection runs asynchronously after page load
    sleep 1

    expect(log_entries.grep(/Content Security Policy/)).to be_empty
  end
end
