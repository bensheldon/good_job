# frozen_string_literal: true

require 'rails_helper'

describe 'Performance Page', :js do
  before do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
    ExampleJob.perform_later
    GoodJob.perform_inline
  end

  it 'renders index properly' do
    visit good_job.root_path
    click_link 'Performance'
    expect(page).to have_css 'h2', text: 'Performance'

    expect(page).to have_content 'ExampleJob'
  end

  it 'renders show properly' do
    visit good_job.root_path
    click_link 'Performance'
    click_link 'ExampleJob'

    expect(page).to have_css 'h2', text: 'Performance - ExampleJob'
  end
end
