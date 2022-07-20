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

  resources :cron_entries, only: %i[index show], param: :cron_key do
    member do
      post :enqueue
      put :enable
      put :disable
    end
  end

  resources :processes, only: %i[index]

  scope :assets, controller: :assets do
    constraints(format: :css) do
      get :bootstrap, action: :bootstrap_css
      get :style, action: :style_css
    end

    constraints(format: :js) do
      get :bootstrap, action: :bootstrap_js
      get :chartjs, action: :chartjs_js
      get :rails_ujs, action: :rails_ujs_js
      get :es_module_shims, action: :es_module_shims_js
      get "modules/:module", action: :modules_js, as: :modules
      get :scripts, action: :scripts_js
    end
  end
end
