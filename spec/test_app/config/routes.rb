Rails.application.routes.draw do
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
  mount GoodJob::Engine => "/good_job"

  get :create_job, to: 'application#create_job'
end
