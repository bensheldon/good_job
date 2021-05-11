module GoodJob
  #
  # Adds Postgres advisory locking capabilities to an ActiveRecord record.
  # For details on advisory locks, see the Postgres documentation:
  # - {https://www.postgresql.org/docs/current/explicit-locking.html#ADVISORY-LOCKS Advisory Locks Overview}
  # - {https://www.postgresql.org/docs/current/functions-admin.html#FUNCTIONS-ADVISORY-LOCKS Advisory Locks Functions}
  #
  # @example Add this concern to a +MyRecord+ class:
  #   class MyRecord < ActiveRecord::Base
  #     include Lockable
  #
  #     def my_method
  #       ...
  #     end
  #   end
  #
  module Lockable
    extend ActiveSupport::Concern

    # Indicates an advisory lock is already held on a record by another
    # database session.
    RecordAlreadyAdvisoryLockedError = Class.new(StandardError)

    included do
      # Attempt to acquire an advisory lock on the selected records and
      # return only those records for which a lock could be acquired.
      # @!method advisory_lock
      # @!scope class
      # @return [ActiveRecord::Relation]
      #   A relation selecting only the records that were locked.
      scope :advisory_lock, (lambda do
        original_query = self

        cte_table = Arel::Table.new(:rows)
        cte_query = original_query.select(primary_key).except(:limit)
        cte_type = if supports_cte_materialization_specifiers?
                     'MATERIALIZED'
                   else
                     ''
                   end

        composed_cte = Arel::Nodes::As.new(cte_table, Arel::Nodes::SqlLiteral.new([cte_type, "(", cte_query.to_sql, ")"].join(' ')))

        query = cte_table.project(cte_table[:id])
                         .with(composed_cte)
                         .where(Arel.sql(sanitize_sql_for_conditions(["pg_try_advisory_lock(('x' || substr(md5(:table_name || #{connection.quote_table_name(cte_table.name)}.#{quoted_primary_key}::text), 1, 16))::bit(64)::bigint)", { table_name: table_name }])))

        limit = original_query.arel.ast.limit
        query.limit = limit.value if limit.present?

        unscoped.where(arel_table[primary_key].in(query)).merge(original_query.only(:order))
      end)

      # Joins the current query with Postgres's +pg_locks+ table (it provides
      # data about existing locks) such that each row in the main query joins
      # to all the advisory locks associated with that row.
      #
      # For details on +pg_locks+, see
      # {https://www.postgresql.org/docs/current/view-pg-locks.html}.
      # @!method joins_advisory_locks
      # @!scope class
      # @return [ActiveRecord::Relation]
      # @example Get the records that have a session awaiting a lock:
      #   MyLockableRecord.joins_advisory_locks.where("pg_locks.granted = ?", false)
      scope :joins_advisory_locks, (lambda do
        join_sql = <<~SQL.squish
          LEFT JOIN pg_locks ON pg_locks.locktype = 'advisory'
            AND pg_locks.objsubid = 1
            AND pg_locks.classid = ('x' || substr(md5(:table_name || #{quoted_table_name}.#{quoted_primary_key}::text), 1, 16))::bit(32)::int
            AND pg_locks.objid = (('x' || substr(md5(:table_name || #{quoted_table_name}.#{quoted_primary_key}::text), 1, 16))::bit(64) << 32)::bit(32)::int
        SQL

        joins(sanitize_sql_for_conditions([join_sql, { table_name: table_name }]))
      end)

      # Find records that do not have an advisory lock on them.
      # @!method advisory_unlocked
      # @!scope class
      # @return [ActiveRecord::Relation]
      scope :advisory_unlocked, -> { joins_advisory_locks.where(pg_locks: { locktype: nil }) }

      # Find records that have an advisory lock on them.
      # @!method advisory_locked
      # @!scope class
      # @return [ActiveRecord::Relation]
      scope :advisory_locked, -> { joins_advisory_locks.where.not(pg_locks: { locktype: nil }) }

      # Find records with advisory locks owned by the current Postgres
      # session/connection.
      # @!method advisory_locked
      # @!scope class
      # @return [ActiveRecord::Relation]
      scope :owns_advisory_locked, -> { joins_advisory_locks.where('"pg_locks"."pid" = pg_backend_pid()') }

      # Whether an advisory lock should be acquired in the same transaction
      # that created the record.
      #
      # This helps prevent another thread or database session from acquiring a
      # lock on the record between the time you create it and the time you
      # request a lock, since other sessions will not be able to see the new
      # record until the transaction that creates it is completed (at which
      # point you have already acquired the lock).
      #
      # @example
      #   record = MyLockableRecord.create(create_with_advisory_lock: true)
      #   record.advisory_locked?
      #   => true
      #
      # @return [Boolean]
      attr_accessor :create_with_advisory_lock

      after_create -> { advisory_lock }, if: :create_with_advisory_lock
    end

    class_methods do
      # Acquires an advisory lock on the selected record(s) and safely releases
      # it after the passed block is completed. The block will be passed an
      # array of the locked records as its first argument.
      #
      # Note that this will not block and wait for locks to be acquired.
      # Instead, it will acquire a lock on all the selected records that it
      # can (as in {Lockable.advisory_lock}) and only pass those that could be
      # locked to the block.
      #
      # @yield [Array<Lockable>] the records that were successfully locked.
      # @return [Object] the result of the block.
      #
      # @example Work on the first two +MyLockableRecord+ objects that could be locked:
      #   MyLockableRecord.order(created_at: :asc).limit(2).with_advisory_lock do |record|
      #     do_something_with record
      #   end
      def with_advisory_lock
        raise ArgumentError, "Must provide a block" unless block_given?

        records = advisory_lock.to_a
        begin
          yield(records)
        ensure
          records.each(&:advisory_unlock)
        end
      end

      def supports_cte_materialization_specifiers?
        return @_supports_cte_materialization_specifiers if defined?(@_supports_cte_materialization_specifiers)

        @_supports_cte_materialization_specifiers = connection.postgresql_version >= 120000
      end
    end

    # Acquires an advisory lock on this record if it is not already locked by
    # another database session. Be careful to ensure you release the lock when
    # you are done with {#advisory_unlock} (or {#advisory_unlock!} to release
    # all remaining locks).
    # @return [Boolean] whether the lock was acquired.
    def advisory_lock
      query = <<~SQL.squish
        SELECT 1 AS one
        WHERE pg_try_advisory_lock(('x'||substr(md5($1 || $2::text), 1, 16))::bit(64)::bigint)
      SQL
      binds = [[nil, self.class.table_name], [nil, send(self.class.primary_key)]]
      self.class.connection.exec_query(pg_or_jdbc_query(query), 'GoodJob::Lockable Advisory Lock', binds).any?
    end

    # Releases an advisory lock on this record if it is locked by this database
    # session. Note that advisory locks stack, so you must call
    # {#advisory_unlock} and {#advisory_lock} the same number of times.
    # @return [Boolean] whether the lock was released.
    def advisory_unlock
      query = <<~SQL.squish
        SELECT 1 AS one
        WHERE pg_advisory_unlock(('x'||substr(md5($1 || $2::text), 1, 16))::bit(64)::bigint)
      SQL
      binds = [[nil, self.class.table_name], [nil, send(self.class.primary_key)]]
      self.class.connection.exec_query(pg_or_jdbc_query(query), 'GoodJob::Lockable Advisory Unlock', binds).any?
    end

    # Acquires an advisory lock on this record or raises
    # {RecordAlreadyAdvisoryLockedError} if it is already locked by another
    # database session.
    # @raise [RecordAlreadyAdvisoryLockedError]
    # @return [Boolean] +true+
    def advisory_lock!
      result = advisory_lock
      result || raise(RecordAlreadyAdvisoryLockedError)
    end

    # Acquires an advisory lock on this record and safely releases it after the
    # passed block is completed. If the record is locked by another database
    # session, this raises {RecordAlreadyAdvisoryLockedError}.
    #
    # @yield Nothing
    # @return [Object] The result of the block.
    #
    # @example
    #   record = MyLockableRecord.first
    #   record.with_advisory_lock do
    #     do_something_with record
    #   end
    def with_advisory_lock
      raise ArgumentError, "Must provide a block" unless block_given?

      advisory_lock!
      yield
    ensure
      advisory_unlock unless $ERROR_INFO.is_a? RecordAlreadyAdvisoryLockedError
    end

    # Tests whether this record has an advisory lock on it.
    # @return [Boolean]
    def advisory_locked?
      query = <<~SQL.squish
        SELECT 1 AS one
        FROM pg_locks
        WHERE pg_locks.locktype = 'advisory'
          AND pg_locks.objsubid = 1
          AND pg_locks.classid = ('x' || substr(md5($1 || $2::text), 1, 16))::bit(32)::int
          AND pg_locks.objid = (('x' || substr(md5($3 || $4::text), 1, 16))::bit(64) << 32)::bit(32)::int
      SQL
      binds = [[nil, self.class.table_name], [nil, send(self.class.primary_key)], [nil, self.class.table_name], [nil, send(self.class.primary_key)]]
      self.class.connection.exec_query(pg_or_jdbc_query(query), 'GoodJob::Lockable Advisory Locked?', binds).any?
    end

    # Tests whether this record is locked by the current database session.
    # @return [Boolean]
    def owns_advisory_lock?
      query = <<~SQL.squish
        SELECT 1 AS one
        FROM pg_locks
        WHERE pg_locks.locktype = 'advisory'
          AND pg_locks.objsubid = 1
          AND pg_locks.classid = ('x' || substr(md5($1 || $2::text), 1, 16))::bit(32)::int
          AND pg_locks.objid = (('x' || substr(md5($3 || $4::text), 1, 16))::bit(64) << 32)::bit(32)::int
          AND pg_locks.pid = pg_backend_pid()
      SQL
      binds = [[nil, self.class.table_name], [nil, send(self.class.primary_key)], [nil, self.class.table_name], [nil, send(self.class.primary_key)]]
      self.class.connection.exec_query(pg_or_jdbc_query(query), 'GoodJob::Lockable Owns Advisory Lock?', binds).any?
    end

    # Releases all advisory locks on the record that are held by the current
    # database session.
    # @return [void]
    def advisory_unlock!
      advisory_unlock while advisory_locked?
    end

    private

    # @param query [String]
    # @return [Boolean]
    def pg_or_jdbc_query(query)
      if Concurrent.on_jruby?
        # Replace $1 bind parameters with ?
        query.gsub(/\$\d*/, '?')
      else
        query
      end
    end
  end
end
