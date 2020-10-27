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
        composed_cte = Arel::Nodes::As.new(cte_table, original_query.select(primary_key).except(:limit).arel)

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

      # @!attribute [r] create_with_advisory_lock
      # @return [Boolean]
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
    end

    # Acquires an advisory lock on this record if it is not already locked by
    # another database session. Be careful to ensure you release the lock when
    # you are done with {#advisory_unlock} (or {#advisory_unlock!} to release
    # all remaining locks).
    # @return [Boolean] whether the lock was acquired.
    def advisory_lock
      where_sql = <<~SQL.squish
        pg_try_advisory_lock(('x' || substr(md5(:table_name || :id::text), 1, 16))::bit(64)::bigint)
      SQL
      self.class.unscoped.exists?([where_sql, { table_name: self.class.table_name, id: send(self.class.primary_key) }])
    end

    # Releases an advisory lock on this record if it is locked by this database
    # session. Note that advisory locks stack, so you must call
    # {#advisory_unlock} and {#advisory_lock} the same number of times.
    # @return [Boolean] whether the lock was released.
    def advisory_unlock
      where_sql = <<~SQL.squish
        pg_advisory_unlock(('x' || substr(md5(:table_name || :id::text), 1, 16))::bit(64)::bigint)
      SQL
      self.class.unscoped.exists?([where_sql, { table_name: self.class.table_name, id: send(self.class.primary_key) }])
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
      self.class.unscoped.advisory_locked.exists?(id: send(self.class.primary_key))
    end

    # Tests whether this record is locked by the current database session.
    # @return [Boolean]
    def owns_advisory_lock?
      self.class.unscoped.owns_advisory_locked.exists?(id: send(self.class.primary_key))
    end

    # Releases all advisory locks on the record that are held by the current
    # database session.
    # @return [void]
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
