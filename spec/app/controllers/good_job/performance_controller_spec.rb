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

    it "raises a 404 when the job doesn't exist" do
      expect do
        get :show, params: { id: "Missing" }
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe '#pause' do
    it 'can pause a queue' do
      post :pause, params: { queue_name: 'default' }
      expect(GoodJob::Setting.where(key: :paused_queues).pick(:value)).to include('default')
      expect(response).to redirect_to action: :index
      expect(flash[:notice]).to eq('Paused successfully')
    end

    it 'can pause a job class' do
      post :pause, params: { job_class: 'MyJob' }
      expect(GoodJob::Setting.where(key: :paused_job_classes).pick(:value)).to include('MyJob')
      expect(response).to redirect_to action: :index
      expect(flash[:notice]).to eq('Paused successfully')
    end
  end

  describe '#unpause' do
    it 'can unpause a queue' do
      GoodJob::Setting.pause(queue: 'default')
      delete :unpause, params: { queue_name: 'default' }
      expect(GoodJob::Setting.where(key: :paused_queues).pick(:value)).not_to include('default')
      expect(response).to redirect_to action: :index
      expect(flash[:notice]).to eq('Unpaused successfully')
    end

    it 'can unpause a job class' do
      GoodJob::Setting.pause(job_class: 'MyJob')
      delete :unpause, params: { job_class: 'MyJob' }
      expect(GoodJob::Setting.where(key: :paused_job_classes).pick(:value)).not_to include('MyJob')
      expect(response).to redirect_to action: :index
      expect(flash[:notice]).to eq('Unpaused successfully')
    end
  end
end
