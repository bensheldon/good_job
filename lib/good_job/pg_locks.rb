module GoodJob
  class PgLocks < ActiveRecord::Base
    self.table_name = 'pg_locks'.freeze
  end
end
