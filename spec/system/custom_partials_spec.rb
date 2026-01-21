# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Custom partials' do
  around do |example|
    perform_good_job_external do
      example.run
    end
  end

  it 'renders custom partials on the Job#show page' do
    ExampleJob.perform_later
    job = GoodJob::Job.last

    visit good_job.job_path(job.id)
    expect(page).to have_content 'ExampleJob'
    expect(page).to have_css ".custom-job-details-for-demo"
    expect(page).to have_no_css ".custom-execution-details-for-demo"

    GoodJob.perform_inline
    visit good_job.job_path(job.id)
    expect(page).to have_css ".custom-execution-details-for-demo"
  end
end
