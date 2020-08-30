module GoodJob
  #
  # +ActiveRecord::Base+ model for the Postgres pg_locks view.
  #
  class PgLocks < ActiveRecord::Base
    self.table_name = 'pg_locks'.freeze
  end
end
