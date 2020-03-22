module GoodJob
  class PgLocks < ActiveRecord::Base
    self.table_name = 'pg_locks'.freeze

    # https://www.postgresql.org/docs/9.6/view-pg-locks.html
    # Advisory locks can be acquired on keys consisting of either a single bigint value or two integer values.
    # A bigint key is displayed with its high-order half in the classid column, its low-order half in the objid column, and objsubid equal to 1.
    # The original bigint value can be reassembled with the expression (classid::bigint << 32) | objid::bigint.
    # Integer keys are displayed with the first key in the classid column, the second key in the objid column, and objsubid equal to 2.
    # The actual meaning of the keys is up to the user. Advisory locks are local to each database, so the database column is meaningful for an advisory lock.
    def self.advisory_lock_details
      connection.select <<~SQL
        SELECT *
        FROM pg_locks
        WHERE
          locktype = 'advisory' AND
          objsubid = 1
      SQL
    end
  end
end
