# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Custom partials' do
  before do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
    ExampleJob.perform_later
  end

  it 'renders custom partials on the Job#show page' do
    job = GoodJob::Job.last
    visit good_job.job_path(job.id)
    expect(page).to have_content 'ExampleJob'
    expect(page).to have_css ".custom-job-details-for-demo"
    expect(page).to have_no_css ".custom-execution-details-for-demo"

    GoodJob.perform_inline
    visit good_job.job_path(job.id)
    expect(page).to have_css ".custom-execution-details-for-demo"
  end

  it 'renders custom job index details partial on the jobs index page' do
    visit good_job.jobs_path
    expect(page).to have_content 'ExampleJob'
    expect(page).to have_css '.custom-job-index-details-for-demo'
  end
end
