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

  it "can pause and unpause jobs" do
    ExampleJob.set(queue: "elephant").perform_later
    GoodJob.perform_inline # populate the executions table

    visit good_job.root_path

    click_on "Performance"

    expect(page).to have_content "ExampleJob"
    expect(page).to have_content "elephant"

    # Pause queue
    accept_confirm { click_on "Pause elephant" }
    expect(page).to have_content "Unpause elephant"
    expect(GoodJob.paused?(queue: "elephant")).to eq true

    ExampleJob.set(queue: "elephant").perform_later
    GoodJob.perform_inline
    expect(GoodJob::Job.unfinished.size).to eq 1

    # Unpause queue
    accept_confirm { click_on "Unpause elephant" }
    expect(page).to have_content "Pause elephant"
    expect(GoodJob.paused?(queue: "elephant")).to eq false

    GoodJob.perform_inline
    expect(GoodJob::Job.unfinished.size).to eq 0

    # Pause job class
    accept_confirm { click_on "Pause ExampleJob" }
    expect(page).to have_content "Unpause ExampleJob"
    expect(GoodJob.paused?(job_class: "ExampleJob")).to eq true

    ExampleJob.set(queue: "elephant").perform_later
    GoodJob.perform_inline
    expect(GoodJob::Job.unfinished.size).to eq 1

    # Unpause job class
    accept_confirm { click_on "Unpause ExampleJob" }
    expect(page).to have_content "Pause ExampleJob"
    expect(GoodJob.paused?(job_class: "ExampleJob")).to eq false

    GoodJob.perform_inline
    expect(GoodJob::Job.unfinished.size).to eq 0
  end
end
