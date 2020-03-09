module GoodJob
  module Lockable
    extend ActiveSupport::Concern

    RecordAlreadyAdvisoryLockedError = Class.new(StandardError)

    included do
      scope :joins_advisory_locks, (lambda do
        joins(<<~SQL)
          LEFT JOIN pg_locks ON pg_locks.locktype = 'advisory'
            AND pg_locks.objsubid = 1
            AND pg_locks.classid = ('x'||substr(md5(good_jobs.id::text), 1, 16))::bit(32)::int
            AND pg_locks.objid = (('x'||substr(md5(good_jobs.id::text), 1, 16))::bit(64) << 32)::bit(32)::int
        SQL
      end)

      scope :advisory_unlocked, -> { joins_advisory_locks.where(pg_locks: { locktype: nil }) }

      def self.first_advisory_locked_row(query)
        find_by_sql(<<~SQL).first
          WITH rows AS (#{query.to_sql})
          SELECT rows.*
          FROM rows
          WHERE pg_try_advisory_lock(('x'||substr(md5(id::text), 1, 16))::bit(64)::bigint)
          LIMIT 1
        SQL
      end
      # private_class_method :first_advisory_locked_row

      # https://www.postgresql.org/docs/9.6/view-pg-locks.html
      # Advisory locks can be acquired on keys consisting of either a single bigint value or two integer values.
      # A bigint key is displayed with its high-order half in the classid column, its low-order half in the objid column, and objsubid equal to 1.
      # The original bigint value can be reassembled with the expression (classid::bigint << 32) | objid::bigint.
      # Integer keys are displayed with the first key in the classid column, the second key in the objid column, and objsubid equal to 2.
      # The actual meaning of the keys is up to the user. Advisory locks are local to each database, so the database column is meaningful for an advisory lock.
      def self.advisory_lock_details
        connection.select("SELECT * FROM pg_locks WHERE locktype = 'advisory' AND objsubid = 1")
      end

      def advisory_lock
        self.class.connection.execute(sanitize_sql_for_conditions(["SELECT 1 as one WHERE pg_try_advisory_lock(('x'||substr(md5(?), 1, 16))::bit(64)::bigint)", id])).ntuples.positive?
      end

      def advisory_lock!
        result = advisory_lock
        result || raise(RecordAlreadyAdvisoryLockedError)
      end

      def with_advisory_lock
        advisory_lock!
        yield
      rescue StandardError => e
        advisory_unlock unless e.is_a? RecordAlreadyAdvisoryLockedError
        raise
      end

      def advisory_locked?
        self.class.connection.execute(<<~SQL).ntuples.positive?
          SELECT 1 as one
          FROM pg_locks
          WHERE
            locktype = 'advisory'
            AND objsubid = 1
            AND classid = ('x'||substr(md5('#{id}'), 1, 16))::bit(32)::int
            AND objid = (('x'||substr(md5('#{id}'), 1, 16))::bit(64) << 32)::bit(32)::int
        SQL
      end

      def owns_advisory_lock?
        self.class.connection.execute(<<~SQL).ntuples.positive?
          SELECT 1 as one
          FROM pg_locks
          WHERE
            locktype = 'advisory'
            AND objsubid = 1
            AND classid = ('x'||substr(md5('#{id}'), 1, 16))::bit(32)::int
            AND objid = (('x'||substr(md5('#{id}'), 1, 16))::bit(64) << 32)::bit(32)::int
            AND pid = pg_backend_pid()
        SQL
      end

      def advisory_unlock
        self.class.connection.execute("SELECT pg_advisory_unlock(('x'||substr(md5('#{id}'), 1, 16))::bit(64)::bigint)").first["pg_advisory_unlock"]
      end

      def advisory_unlock!
        advisory_unlock while advisory_locked?
      end

      private

      def sanitize_sql_for_conditions(*args)
        # Made public in Rails 5.2
        self.class.send(:sanitize_sql_for_conditions, *args)
      end
    end
  end
end
