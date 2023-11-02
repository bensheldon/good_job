# frozen_string_literal: true

require 'rails_helper'

describe 'Light and Dark Themes', :js do
  specify do
    visit good_job.jobs_path
    expect(page).to have_css('html[data-bs-theme="light"]')

    find('button[data-theme-target="dropdown"]').click
    click_button 'Dark'
    expect(page).to have_css('html[data-bs-theme="dark"]')

    visit good_job.jobs_path
    expect(page).to have_css('html[data-bs-theme="dark"]')
  end
end
