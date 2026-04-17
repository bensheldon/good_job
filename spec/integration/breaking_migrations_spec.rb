# frozen_string_literal: true

require 'rails_helper'

# GoodJob's packaged update migrations add new columns that must remain optional
# until the next major release, so that running them is not a breaking change
# requiring a Semver major version bump. These tests verify that GoodJob continues
# to function correctly when those columns are absent.
#
# To add a new column, append an entry: { model: GoodJob::SomeModel, column: :column_name }
NEW_OPTIONAL_COLUMNS = [
  { model: GoodJob::Job, column: :lock_type },
  { model: GoodJob::BatchRecord, column: :jobs_finished_at },
].freeze

RSpec.describe 'Breaking migrations' do
  around do |example|
    dropped = []
    NEW_OPTIONAL_COLUMNS.each do |scenario|
      col = scenario[:model].columns_hash.fetch(scenario[:column].to_s)
      col_options = { limit: col.limit, precision: col.precision, null: col.null, default: col.default }.compact
      scenario[:model].connection_pool.with_connection { |c| c.remove_column(scenario[:model].table_name, scenario[:column]) }
      scenario[:model].reset_column_information
      dropped << scenario.merge(col_type: col.type, col_options: col_options)
    end

    example.run
  ensure
    dropped.each do |scenario|
      scenario[:model].connection_pool.with_connection do |c|
        c.add_column(scenario[:model].table_name, scenario[:column], scenario[:col_type], **scenario[:col_options]) unless c.column_exists?(scenario[:model].table_name, scenario[:column])
      end
      scenario[:model].reset_column_information
    end
  end

  before do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
    GoodJob.preserve_job_records = true

    stub_const "RUN_JOBS", Concurrent::Array.new
    stub_const 'TestJob', (Class.new(ActiveJob::Base) do
      def perform
        RUN_JOBS << provider_job_id
      end
    end)
  end

  it 'can enqueue and perform a job' do
    TestJob.perform_later

    performer = GoodJob::JobPerformer.new('*')
    scheduler = GoodJob::Scheduler.new(performer, max_threads: 1)
    scheduler.create_thread

    wait_until(max: 5, increments_of: 0.1) { expect(GoodJob::Job.last.finished_at).to be_present }
    scheduler.shutdown

    expect(RUN_JOBS.size).to eq 1
  end

  it 'can enqueue and complete a batch' do
    batch = GoodJob::Batch.enqueue { TestJob.perform_later }

    GoodJob.perform_inline

    batch.reload
    expect(batch).to be_finished
    expect(batch).to be_succeeded
  end
end
