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
    expect(page).not_to have_css ".custom-execution-details-for-demo"

    GoodJob.perform_inline
    visit good_job.job_path(job.id)
    expect(page).to have_css ".custom-execution-details-for-demo"
  end
end
