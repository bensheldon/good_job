# frozen_string_literal: true

require 'rails_helper'

describe GoodJob::ExecutionsController do
  before do
    allow(GoodJob).to receive_messages(preserve_job_records: true, retry_on_unhandled_error: false)
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :inline)
    ExampleJob.perform_later(ExampleJob::DEAD_TYPE)
  end

  let(:execution) { GoodJob::Execution.order(:created_at).last }

  describe 'GET #show' do
    it "renders the execution's full trace and serialized params as turbo frames" do
      get good_job.job_execution_path(execution.active_job_id, execution.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("<html")
      expect(response.body).to include(%(<turbo-frame id="#{ActionView::RecordIdentifier.dom_id(execution, :full_trace)}">))
      expect(response.body).to include(%(<turbo-frame id="#{ActionView::RecordIdentifier.dom_id(execution, :serialized_params)}">))
      expect(response.body).to include(CGI.escapeHTML(execution.error_backtrace.first))
    end

    it 'returns not found when the execution does not belong to the job' do
      get good_job.job_execution_path(SecureRandom.uuid, execution.id)

      expect(response).to have_http_status(:not_found)
    end
  end
end
