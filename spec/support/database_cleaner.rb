RSpec.configure do |config|
  # Disabled because this causes the same database connection to be reused across threads
  # which causes Advisory Locks to not be effective because they are locked per-connection/per-thread.
  config.use_transactional_fixtures = false

  config.before(:suite) do
    DatabaseCleaner.strategy = :truncation
    DatabaseCleaner.clean_with :truncation
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end
end
