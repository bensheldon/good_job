# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  config.cache_classes = false
  config.eager_load = false

  # Raises error for missing translations.
  if Gem::Version.new(Rails.version) < Gem::Version.new('6.1')
    config.action_view.raise_on_missing_translations = true
  else
    config.i18n.raise_on_missing_translations = true
  end

  if ActiveModel::Type::Boolean.new.cast(ENV['RAILS_LOG_TO_STDOUT'])
    logger = ActiveSupport::Logger.new(STDOUT)
    logger.formatter = config.log_formatter
    config.logger = ActiveSupport::TaggedLogging.new(logger)
  end
end
