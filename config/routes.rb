# frozen_string_literal: true

GoodJob::Engine.routes.draw do
  root 'jobs#redirect_to_index'

  resources :jobs, only: %i[index show destroy] do
    collection do
      get :mass_update, to: redirect(path: 'jobs')
      put :mass_update
    end

    member do
      put :discard
      put :force_discard
      put :reschedule
      put :retry
    end
  end
  get 'jobs/metrics/primary_nav', to: 'metrics#primary_nav', as: :metrics_primary_nav
  get 'jobs/metrics/job_status', to: 'metrics#job_status', as: :metrics_job_status

  resources :batches, only: %i[index show] do
    member do
      put :retry
    end
  end

  resources :cron_entries, only: %i[index show], param: :cron_key do
    member do
      post :enqueue
      put :enable
      put :disable
    end
  end

  resources :processes, only: %i[index]
  resources :performance, only: %i[index show]
  resources :pauses, only: %i[index] do
    collection do
      post :create
      delete :destroy
    end
  end
  resources :cleaner, only: %i[index]

  scope :frontend, controller: :frontends, defaults: { version: GoodJob::VERSION.tr(".", "-") } do
    get "modules/:version/:id", action: :module, as: :frontend_module, constraints: { format: 'js' }
    get "static/:version/:id", action: :static, as: :frontend_static
  end
end
