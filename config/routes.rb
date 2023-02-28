# frozen_string_literal: true
GoodJob::Engine.routes.draw do
  root to: redirect(path: 'jobs')

  resources :jobs, only: %i[index show destroy] do
    collection do
      get :mass_update, to: redirect(path: 'jobs')
      put :mass_update
    end

    member do
      put :discard
      put :reschedule
      put :retry
    end
  end

  resources :batches, only: %i[index show]

  resources :cron_entries, only: %i[index show], param: :cron_key do
    member do
      post :enqueue
      put :enable
      put :disable
    end
  end

  resources :processes, only: %i[index]

  scope :assets, controller: :assets do
    get "modules/:name", action: :module, as: :module_asset, constraints: { format: 'js' }
    get "static/:name", action: :static, as: :static_asset, constraints: { format: %w[css js] }
  end
end
