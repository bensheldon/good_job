# frozen_string_literal: true
GoodJob::Engine.routes.draw do
  root to: 'executions#index'
  resources :cron_schedules, only: %i[index]
  resources :jobs, only: %i[index show]
  resources :executions, only: %i[destroy]

  scope controller: :assets do
    constraints(format: :css) do
      get :bootstrap, action: :bootstrap_css
      get :chartist, action: :chartist_css
      get :style, action: :style_css
    end

    constraints(format: :js) do
      get :bootstrap, action: :bootstrap_js
      get :chartist, action: :chartist_js
    end
  end
end
