# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  config.cache_classes = true
  config.eager_load = ENV["CI"].present?

  # Do not use dotenv feature to autorestore ENV after tests
  config.dotenv.autorestore = false if config.respond_to?(:dotenv)

  config.active_job.queue_adapter = :test

  # Raises error for missing translations.
  if Gem::Version.new(Rails.version) < Gem::Version.new('6.1')
    config.action_view.raise_on_missing_translations = true
  else
    config.i18n.raise_on_missing_translations = true
  end

  config.colorize_logging = false if ENV["CI"]
  if ActiveModel::Type::Boolean.new.cast(ENV['RAILS_LOG_TO_STDOUT'])
    logger = ActiveSupport::Logger.new(STDOUT)
    logger.formatter = config.log_formatter
    config.logger = ActiveSupport::TaggedLogging.new(logger)
  end
end
