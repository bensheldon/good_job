# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join("config/warmup")

describe Warmup do
  before do
    allow(GoodJob).to receive_messages(preserve_job_records: true, retry_on_unhandled_error: false)
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :inline)
    ExampleJob.perform_later(ExampleJob::ERROR_ONCE_TYPE)
    GoodJob::CronEntry.find(:example).enqueue
  end

  it "renders every warmup page successfully" do
    statuses = described_class.run(Rails.application)

    expect(statuses.keys).to include(
      a_string_matching(%r{\A/good_job/jobs/[0-9a-f-]{36}\?}),
      a_string_matching(%r{\A/good_job/jobs/[^/]+/executions/}),
      a_string_matching(%r{\A/good_job/cron_entries/[^/?]+})
    )
    expect(statuses).to all(satisfy { |_path, status| status == 200 })
  end

  it "performs warmup jobs and removes their records" do
    allow(GoodJob).to receive(:perform_inline).and_call_original

    described_class.run(Rails.application)

    expect(GoodJob).to have_received(:perform_inline).with(described_class::QUEUE, limit: described_class::JOBS)
    expect(GoodJob::Job.where(queue_name: described_class::QUEUE)).to be_empty
  end
end
