GoodJob::Engine.routes.draw do
  root to: 'dashboards#index'
  resources :active_jobs, only: %i[show]
  resources :jobs, only: %i[destroy]

  scope controller: :assets do
    get :bootstrap_css
    get :bootstrap_js
    get :chartist_css
    get :chartist_js
    get :style_css
  end
end
