require_relative 'boot'

require 'rails/all'
require "good_job"
require "good_job/engine"

Bundler.require(*Rails.groups)
require_relative "../lib/thread_name_formatter"

module TestApp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults Gem::Version.new(Rails.version).segments.slice(0..1).join('.').to_f

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.
    #
    config.log_formatter = ThreadNameFormatter.new

    config.active_job.queue_adapter = :good_job

    # config.middleware.insert_before Rack::Sendfile, ActionDispatch::DebugLocks
    config.log_level = :debug

    config.action_controller.include_all_helpers = false

    config.skylight.environments << 'demo' if defined?(Skylight)

    # Set default locale to something not yet translated for GoodJob
    # config.i18n.available_locales = [:pt]
    # config.i18n.default_locale = :pt
  end
end
