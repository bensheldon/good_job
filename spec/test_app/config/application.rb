require_relative 'boot'

require 'rails/all'
require "good_job/engine"

Bundler.require(*Rails.groups)
require "good_job"

module TestApp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    # config.load_defaults 6.0

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.
    #

    # config.middleware.insert_before Rack::Sendfile, ActionDispatch::DebugLocks
    config.log_level = :debug
  end
end

