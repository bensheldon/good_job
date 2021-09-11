# frozen_string_literal: true
require 'rails_helper'

describe 'Cron Schedules', type: :system, js: true do
  it 'renders successfully' do
    visit '/good_job/cron_schedules'
    expect(page).to have_content 'ExampleJob'
  end
end
