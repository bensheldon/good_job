# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoodJob::PerformancesController, type: :controller do
  render_views # seems required for Rails HEAD

  before do
    @routes = GoodJob::Engine.routes
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
    ExampleJob.perform_later
    GoodJob.perform_inline
  end

  describe '#index' do
    it 'renders the index page' do
      get :show
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Performance')
    end
  end
end
