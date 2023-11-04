class ApplicationController < ActionController::Base
  def create_job
    if params[:wait]
      wait = params.fetch(:wait, 2).to_i
      ExampleJob.set(wait: wait).perform_later
    else
      ExampleJob.perform_later
    end

    render plain: 'ok'
  end
end
