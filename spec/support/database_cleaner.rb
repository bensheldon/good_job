# frozen_string_literal: true
RSpec.configure do |config|
  # Disabled because this causes the same database connection to be reused across threads
  # which causes Advisory Locks to not be effective because they are locked per-connection/per-thread.
  config.use_transactional_fixtures = false

  config.before(:suite) do
    ActiveRecord::Tasks::DatabaseTasks.truncate_all
  end

  config.around do |example|
    example.run
    ActiveRecord::Tasks::DatabaseTasks.truncate_all
  end
end
