# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoodJob::PausesController, type: :controller do
  render_views # seems required for Rails HEAD

  around do |example|
    perform_good_job_external do
      example.run
    end
  end

  before do
    @routes = GoodJob::Engine.routes
  end

  describe '#index' do
    it 'renders the index page' do
      get :index
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Pauses')
    end
  end

  describe '#create' do
    it 'can pause a queue' do
      post :create, params: { type: 'queue', value: 'default' }
      expect(GoodJob::Setting.paused(:queues)).to include('default')
      expect(response).to redirect_to action: :index
      expect(flash[:notice]).to eq("Successfully paused queue 'default'")
    end

    it 'can pause a job class' do
      post :create, params: { type: 'job_class', value: 'MyJob' }
      expect(GoodJob::Setting.paused(:job_classes)).to include('MyJob')
      expect(response).to redirect_to action: :index
      expect(flash[:notice]).to eq("Successfully paused job_class 'MyJob'")
    end

    it 'redirects with no action for invalid parameters' do
      expect do
        post :create, params: { type: 'invalid', value: 'something' }
      end.to raise_error(ActionController::BadRequest)

      expect do
        post :create, params: { type: 'queue', value: '' }
      end.to raise_error(ActionController::BadRequest)
    end
  end

  describe '#destroy' do
    it 'can unpause a queue' do
      GoodJob::Setting.pause(queue: 'default')
      delete :destroy, params: { type: 'queue', value: 'default' }
      expect(GoodJob::Setting.paused(:queues)).not_to include('default')
      expect(response).to redirect_to action: :index
      expect(flash[:notice]).to eq("Successfully unpaused queue 'default'")
    end

    it 'can unpause a job class' do
      GoodJob::Setting.pause(job_class: 'MyJob')
      delete :destroy, params: { type: 'job_class', value: 'MyJob' }
      expect(GoodJob::Setting.paused(:job_classes)).not_to include('MyJob')
      expect(response).to redirect_to action: :index
      expect(flash[:notice]).to eq("Successfully unpaused job_class 'MyJob'")
    end

    it 'redirects with no action for invalid parameters' do
      expect do
        delete :destroy, params: { type: 'invalid', value: 'something' }
      end.to raise_error(ActionController::BadRequest)

      expect do
        delete :destroy, params: { type: 'queue', value: '' }
      end.to raise_error(ActionController::BadRequest)
    end
  end
end
