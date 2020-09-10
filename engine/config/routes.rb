GoodJob::Engine.routes.draw do
  root to: 'dashboards#index'
  resources :active_jobs, only: :show
end
