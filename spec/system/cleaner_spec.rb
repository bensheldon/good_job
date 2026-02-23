# frozen_string_literal: true

require 'rails_helper'

describe 'Cleaner Page', :js do
  let(:discarded_job) do
    Timecop.travel 1.hour.ago
    ExampleJob.set(queue: :elephants).perform_later(ExampleJob::DEAD_TYPE)
    5.times do
      Timecop.travel 5.minutes
      GoodJob.perform_inline
    end
    Timecop.return
    GoodJob::Job.order(created_at: :asc).last
  end

  around do |example|
    perform_good_job_inline do
      example.run
    end
  end

  it 'render index properly' do
    visit good_job.root_path
    click_link 'Cleaner'
    expect(page).to have_css 'h2', text: 'Cleaner'
  end

  it 'redirects to jobs discarded page with job filtered' do
    discarded_job

    visit '/good_job/cleaner'

    expect(page).to have_content 'DeadError'

    page.find('table#by-job-class tbody tr:first-child td:nth-child(2)').click_link '1'

    expect(page).to have_css 'h2', text: 'Jobs'
    expect(page).to have_content 'Error: ExampleJob::DeadError'

    expect(find('#filter a.nav-link.active span')).to have_content '1'
  end
end
