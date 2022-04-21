# frozen_string_literal: true
require 'rails_helper'

describe 'Dashboard', type: :system, js: true do
  before do
    allow(GoodJob).to receive(:retry_on_unhandled_error).and_return(false)
    allow(GoodJob).to receive(:preserve_job_records).and_return(true)
  end

  it 'renders chart js' do
    visit '/good_job'
    expect(page).to have_content 'GoodJob 👍'
  end

  it 'renders each top-level page successfully' do
    visit '/good_job'
    expect(page).to have_content 'GoodJob 👍'

    click_on "Jobs"
    expect(page).to have_content 'GoodJob 👍'

    click_on "Cron"
    expect(page).to have_content 'GoodJob 👍'

    click_on "Processes"
    expect(page).to have_content 'GoodJob 👍'
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

    describe 'filtering' do
      let!(:foo_queue_job) { ConfigurableQueueJob.set(wait: 10.minutes).perform_later(queue_as: 'foo') }

      it "can filter by job class" do
        visit good_job.jobs_path

        select "ConfigurableQueueJob", from: "job_class_filter"
        expect(current_url).to match(/job_class=ConfigurableQueueJob/)

        table = page.find("#jobs-table")
        expect(table).to have_selector("tbody tr", count: 1)
        expect(table).to have_content(foo_queue_job.job_id)
      end

      it "can filter by state" do
        visit good_job.jobs_path

        click_on "Scheduled"

        expect(current_url).to match(/state=scheduled/)

        table = page.find("#jobs-table")
        expect(table).to have_selector("tbody tr", count: 2)
        expect(table).to have_content(foo_queue_job.job_id)
      end

      it "can filter by queue" do
        visit good_job.jobs_path

        select "foo", from: "job_queue_filter"
        expect(current_url).to match(/queue_name=foo/)

        table = page.find("#jobs-table")
        expect(table).to have_selector("tbody tr", count: 1)
        expect(table).to have_content(foo_queue_job.job_id)
      end

      it "can filter by multiple variables" do
        visit good_job.jobs_path

        select "ConfigurableQueueJob", from: "job_class_filter"
        select "default", from: "job_queue_filter"

        expect(page).to have_content("No jobs found.")

        select "foo", from: "job_queue_filter"

        expect(page).to have_content(foo_queue_job.job_id)
      end

      it 'can search by argument' do
        visit '/good_job'
        click_on "Jobs"

        expect(page).to have_selector('.active_job_job', count: 3)
        fill_in 'query', with: ExampleJob::DEAD_TYPE
        click_on 'Search'
        expect(page).to have_selector('.active_job_job', count: 1)
      end
    end

    it 'can retry discarded jobs' do
      visit '/good_job'
      click_on "Jobs"

      expect do
        within "##{dom_id(discarded_job)}" do
          accept_confirm { click_on 'Retry job' }
        end
        expect(page).to have_content "Job has been retried"
      end.to change { discarded_job.executions.reload.size }.by(1)
    end

    it 'can discard jobs' do
      visit '/good_job'
      click_on "Jobs"

      expect do
        within "##{dom_id(unfinished_job)}" do
          accept_confirm { click_on 'Discard job' }
        end
        expect(page).to have_content "Job has been discarded"
      end.to change { unfinished_job.head_execution(reload: true).finished_at }.from(nil).to within(1.second).of(Time.current)
    end

    it 'performs batch job actions' do
      visit "/good_job"
      click_on "Jobs"

      expect(page).to have_selector('input[type=checkbox]:checked', count: 0)

      check "toggle_job_ids"
      expect(page).to have_selector('input[type=checkbox]:checked', count: 3)

      uncheck "toggle_job_ids"
      expect(page).to have_selector('input[type=checkbox]:checked', count: 0)

      expect do
        check "toggle_job_ids"
        within("table thead") { accept_confirm { click_on "Reschedule all" } }
        expect(page).to have_selector('input[type=checkbox]:checked', count: 0)
      end.to change { unfinished_job.reload.scheduled_at }.to within(1.second).of(Time.current)

      expect do
        check "toggle_job_ids"
        within("table thead") { accept_confirm { click_on "Discard all" } }
        expect(page).to have_selector('input[type=checkbox]:checked', count: 0)
      end.to change { GoodJob::ActiveJobJob.discarded.count }.from(1).to(2)

      expect do
        check "toggle_job_ids"
        within("table thead") { accept_confirm { click_on "Retry all" } }
        expect(page).to have_selector('input[type=checkbox]:checked', count: 0)
      end.to change { GoodJob::ActiveJobJob.discarded.count }.from(2).to(0)

      visit good_job.jobs_path(limit: 1)
      expect do
        check "toggle_job_ids"
        check "Apply to all 2 jobs"
        within("table thead") { accept_confirm { click_on "Discard all" } }
        expect(page).to have_selector('input[type=checkbox]:checked', count: 0)
      end.to change { GoodJob::ActiveJobJob.discarded.count }.from(0).to(2)
    end
  end

  describe "when changing language" do
    it "changes wording from English to Spanish" do
      visit good_job_path(locale: :en)

      expect(page).to have_content "Processes"
      find("#localeOptions").click
      within ".navbar" do
        click_on "es"
      end
      expect(page).to have_content "Procesos"
    end
  end
end
