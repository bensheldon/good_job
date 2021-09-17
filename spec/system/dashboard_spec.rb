# frozen_string_literal: true
require 'rails_helper'

describe 'Dashboard', type: :system, js: true do
  it 'renders successfully' do
    visit '/good_job'
    expect(page).to have_content 'GoodJob 👍'
  end

  it 'deletes job' do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)

    ExampleJob.perform_later

    visit '/good_job'
    expect(page).to have_content 'ExampleJob'

    click_button('Delete execution')
    expect(page).to have_content 'Job execution deleted'
    expect(page).not_to have_content 'ExampleJob'
  end

  it 'deletes job redirecting back to applied filter' do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)

    ExampleJob.perform_later

    visit '/good_job'
    click_link 'unfinished'
    expect(page).to have_content 'ExampleJob'

    click_button('Delete execution')
    expect(page).to have_content 'Job execution deleted'
    expect(page).not_to have_content 'ExampleJob'
    expect(current_url).to match %r{/good_job/\?state=unfinished}
  end
end
