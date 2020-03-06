module GoodJob
  class Railtie < ::Rails::Railtie
    initializer "good_job.logger" do
      ActiveSupport.on_load(:good_job) { self.logger = ::Rails.logger }
    end
  end
end
