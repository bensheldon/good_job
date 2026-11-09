# frozen_string_literal: true

require 'rails_helper'

describe 'Light and Dark Themes', :js do
  specify do
    visit good_job.jobs_path
    expect(page).to have_css('html[data-bs-theme="light"]')
    expect(page).to have_css('button[data-theme-value-param="auto"].active', visible: :all)

    find('button[data-theme-target="dropdown"]').click
    click_button 'Dark'
    expect(page).to have_css('html[data-bs-theme="dark"]')

    visit good_job.jobs_path
    expect(page).to have_css('html[data-bs-theme="dark"]')
  end

  it 'follows a theme chosen in another tab' do
    visit good_job.jobs_path
    expect(page).to have_css('html[data-bs-theme="light"]')

    page.execute_script(<<~JS)
      localStorage.setItem('good_job-theme', 'dark');
      window.dispatchEvent(new StorageEvent('storage', { key: 'good_job-theme' }));
    JS
    expect(page).to have_css('html[data-bs-theme="dark"]')
    expect(page).to have_css('button[data-theme-value-param="dark"].active', visible: :all)

    page.execute_script(<<~JS)
      localStorage.clear();
      window.dispatchEvent(new StorageEvent('storage', { key: null }));
    JS
    expect(page).to have_css('html[data-bs-theme="light"]')
    expect(page).to have_css('button[data-theme-value-param="auto"].active', visible: :all)
  end
end
