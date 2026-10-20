# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join("config/warmup")

describe Warmup do
  before do
    allow(GoodJob).to receive_messages(preserve_job_records: true, retry_on_unhandled_error: false)
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :inline)
    ExampleJob.perform_later(ExampleJob::ERROR_ONCE_TYPE)
  end

  it "renders every warmup page successfully" do
    statuses = described_class.run(Rails.application)

    expect(statuses.keys).to include(a_string_matching(%r{\A/good_job/jobs/[^/]+/executions/}))
    expect(statuses).to all(satisfy { |_path, status| status == 200 })
  end
end
