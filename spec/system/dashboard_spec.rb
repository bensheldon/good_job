# frozen_string_literal: true
require 'rails_helper'

describe 'Dashboard', type: :system do
  before do
    allow(GoodJob).to receive(:retry_on_unhandled_error).and_return(false)
    allow(GoodJob).to receive(:preserve_job_records).and_return(true)
  end

  it 'renders chart js', js: true do
    visit '/good_job'
    expect(page).to have_content 'GoodJob 👍'
  end

  it 'renders each top-level page successfully' do
    visit '/good_job'
    expect(page).to have_content 'GoodJob 👍'

    click_on "All Executions"
    expect(page).to have_content 'GoodJob 👍'

    click_on "All Jobs"
    expect(page).to have_content 'GoodJob 👍'

    click_on "Cron Schedule"
    expect(page).to have_content 'GoodJob 👍'
  end

  describe 'Executions' do
    it 'deletes executions and redirects back to applied filter' do
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

  describe 'Jobs' do
    let(:unfinished_job) do
      ExampleJob.set(wait: 10.minutes).perform_later
      GoodJob::ActiveJobJob.order(created_at: :asc).last
    end

    let(:discarded_job) do
      ExampleJob.perform_later(ExampleJob::DEAD_TYPE)
    rescue StandardError
      GoodJob::ActiveJobJob.order(created_at: :asc).last
    end

    before do
      ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :inline)
      discarded_job
      ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
      unfinished_job
    end

    it 'can retry discarded jobs' do
      visit '/good_job'
      click_on "All Jobs"

      expect do
        within "##{dom_id(discarded_job)}" do
          click_on 'Retry job'
        end
      end.to change { discarded_job.executions.reload.size }.by(1)
    end

    it 'can discard jobs' do
      visit '/good_job'
      click_on "All Jobs"

      expect do
        within "##{dom_id(unfinished_job)}" do
          click_on 'Discard job'
        end
      end.to change { unfinished_job.head_execution(reload: true).finished_at }.to within(1.second).of(Time.current)
    end
  end
end
