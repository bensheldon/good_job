# frozen_string_literal: true
GoodJob::Engine.routes.draw do
  root to: 'executions#index'

  resources :executions, only: %i[destroy]

  resources :jobs, only: %i[index show] do
    member do
      put :discard
      put :reschedule
      put :retry
    end
  end

  resources :cron_entries, only: %i[index show] do
    member do
      post :enqueue
    end
  end

  resources :processes, only: %i[index]

  scope controller: :assets do
    constraints(format: :css) do
      get :bootstrap, action: :bootstrap_css
      get :style, action: :style_css
    end

    constraints(format: :js) do
      get :bootstrap, action: :bootstrap_js
      get :rails_ujs, action: :rails_ujs_js
      get :chartjs, action: :chartjs_js
      get :scripts, action: :scripts_js
    end
  end
end
