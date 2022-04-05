# frozen_string_literal: true
require 'rails_helper'

describe "requests to jobs endpoint", type: :request do
  before do
    allow(GoodJob).to receive(:preserve_job_records).and_return(true)
    # When spec type is request, ActiveJob::TestHelper is included. It sets the
    # adapter to TestAdapter. We forcibly set the adapter to GJ to create GJ
    # records.
    ExampleJob.enable_test_adapter(GoodJob::Adapter.new(execution_mode: :inline))
  end

  it "renders successfully" do
    ExampleJob.perform_later
    assert_equal 1, GoodJob::Execution.count

    get "/good_job/jobs"

    assert_response :success
  end
end
