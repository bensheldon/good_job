# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoodJob::PerformanceController, type: :controller do
  render_views # seems required for Rails HEAD

  before do
    @routes = GoodJob::Engine.routes
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
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

    it "renders the show page when the job doesn't exist" do
      get :show, params: { id: "Missing" }
      expect(response).to have_http_status(:ok)
    end
  end
end
