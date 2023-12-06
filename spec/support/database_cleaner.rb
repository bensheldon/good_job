# frozen_string_literal: true

RSpec.configure do |config|
  # Disabled because this causes the same database connection to be reused across threads
  # which causes Advisory Locks to not be effective because they are locked per-connection/per-thread.
  config.use_transactional_fixtures = false

  config.before(:suite) do
    ApplicationRecord.connection_handler.clear_active_connections!
    ApplicationRecord.connection_pool.disconnect
    ApplicationRecord.connection_pool.with_connection do |connection|
      connection.truncate_tables(*connection.tables)
    end
  end

  config.around do |example|
    example.run

    ApplicationRecord.connection_handler.clear_active_connections!
    ApplicationRecord.connection_pool.disconnect
    ApplicationRecord.connection_pool.with_connection do |connection|
      connection.truncate_tables(*connection.tables)
    end
  end
end
