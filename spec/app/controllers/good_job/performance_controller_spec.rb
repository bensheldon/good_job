# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoodJob::PerformanceController, type: :controller do
  render_views # seems required for Rails HEAD

  around do |example|
    perform_good_job_external do
      example.run
    end
  end

  before do
    @routes = GoodJob::Engine.routes
    ExampleJob.perform_later
    GoodJob.perform_inline
  end

  describe '#index' do
    it 'renders the index page' do
      get :index
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Performance')
    end
  end

  describe '#show' do
    it 'renders the show page' do
      get :show, params: { id: "ExampleJob" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Performance - ExampleJob')
    end

    it "raises a 404 when the job doesn't exist" do
      expect do
        get :show, params: { id: "Missing" }
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
