# frozen_string_literal: true

require 'rails_helper'

describe 'Performance Page', :js do
  before do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
  end

  it 'renders index properly' do
    ExampleJob.perform_later
    GoodJob.perform_inline

    visit good_job.root_path
    click_link 'Performance'
    expect(page).to have_css 'h2', text: 'Performance'
    expect(page).to have_content 'ExampleJob'
  end

  it 'can select and reset a chart range on the index' do
    ExampleJob.perform_later
    GoodJob.perform_inline

    visit good_job.performance_index_path

    click_button "Open chart time ranges"
    click_link "Last 1 hour"

    expect(page).to have_current_path(/chart_range=1h/)
    expect(page).to have_css(".chart-range-key", text: "1h")

    find("a[aria-label='Reset chart time range']").click

    expect(page).to have_no_current_path(/chart_range=/)
    expect(page).to have_css(".chart-range-key", text: "24h")
    expect(page).to have_css("a[aria-label='Reset chart time range'].disabled")
  end

  it 'renders show properly' do
    ExampleJob.perform_later
    GoodJob.perform_inline

    visit good_job.root_path

    click_link 'Performance'
    expect(page).to have_css "h2", text: "Performance"

    click_link 'ExampleJob'

    expect(page).to have_css 'h2', text: 'Performance - ExampleJob'
    expect(page).to have_no_css(".chart-range-toolbar")
  end
end
