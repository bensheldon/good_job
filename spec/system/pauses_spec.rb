# frozen_string_literal: true

require 'rails_helper'

describe 'Pauses' do
  around do |example|
    perform_good_job_external do
      example.run
    end
  end

  it "can pause and unpause jobs" do
    ExampleJob.perform_later
    GoodJob.perform_inline

    visit good_job.root_path

    click_on "Pauses"

    # Pause queue
    select "Queue", from: "Pause Type"
    fill_in "Value", with: "elephant"
    click_on "Pause"

    expect(page).to have_content "elephant"
    expect(GoodJob.paused?(queue: "elephant")).to eq true

    ExampleJob.set(queue: "elephant").perform_later
    GoodJob.perform_inline
    expect(GoodJob::Job.unfinished.size).to eq 1

    # Unpause queue
    within "li", text: "elephant" do
      accept_confirm { click_on "Resume" }
    end
    expect(page).to have_content "Successfully unpaused"
    expect(GoodJob.paused?(queue: "elephant")).to eq false

    GoodJob.perform_inline
    expect(GoodJob::Job.unfinished.size).to eq 0

    # Pause job class
    select "Job Class", from: "Pause Type"
    fill_in "Value", with: "ExampleJob"
    click_on "Pause"

    expect(page).to have_content "ExampleJob"
    expect(GoodJob.paused?(job_class: "ExampleJob")).to eq true

    ExampleJob.set(queue: "elephant").perform_later
    GoodJob.perform_inline
    expect(GoodJob::Job.unfinished.size).to eq 1

    # Unpause job class
    within "li", text: "ExampleJob" do
      accept_confirm { click_on "Resume" }
    end
    expect(page).to have_content "Successfully unpaused"
    expect(GoodJob.paused?(job_class: "ExampleJob")).to eq false

    GoodJob.perform_inline
    expect(GoodJob::Job.unfinished.size).to eq 0

    # Pause label
    select "Label", from: "Pause Type"
    fill_in "Value", with: "important"
    click_on "Pause"

    expect(page).to have_content "important"
    expect(GoodJob.paused?(label: "important")).to eq true

    ExampleJob.set(good_job_labels: ["important"]).perform_later
    GoodJob.perform_inline
    expect(GoodJob::Job.unfinished.size).to eq 1

    # Unpause label
    within "li", text: "important" do
      accept_confirm { click_on "Resume" }
    end
    expect(page).to have_content "Successfully unpaused"
    expect(GoodJob.paused?(label: "important")).to eq false

    GoodJob.perform_inline
    expect(GoodJob::Job.unfinished.size).to eq 0
  end
end
