# frozen_string_literal: true
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
      # Default column to be used when creating Advisory Locks
      class_attribute :advisory_lockable_column, instance_accessor: false, default: nil

      # Default Postgres function to be used for Advisory Locks
      class_attribute :advisory_lockable_function, default: "pg_try_advisory_lock"

      # Attempt to acquire an advisory lock on the selected records and
      # return only those records for which a lock could be acquired.
      # @!method advisory_lock(column: _advisory_lockable_column, function: advisory_lockable_function)
      # @!scope class
      # @param column [String, Symbol] column values to Advisory Lock against
      # @param function [String, Symbol]  Postgres Advisory Lock function name to use
      # @return [ActiveRecord::Relation]
      #   A relation selecting only the records that were locked.
      scope :advisory_lock, (lambda do |column: _advisory_lockable_column, function: advisory_lockable_function|
        original_query = self

        cte_table = Arel::Table.new(:rows)
        cte_query = original_query.select(primary_key, column).except(:limit)
        cte_type = if supports_cte_materialization_specifiers?
                     'MATERIALIZED'
                   else
                     ''
                   end

        composed_cte = Arel::Nodes::As.new(cte_table, Arel::Nodes::SqlLiteral.new([cte_type, "(", cte_query.to_sql, ")"].join(' ')))
        query = cte_table.project(cte_table[:id])
                         .with(composed_cte)
                         .where(Arel.sql(sanitize_sql_for_conditions(["#{function}(('x' || substr(md5(:table_name || '-' || #{connection.quote_table_name(cte_table.name)}.#{connection.quote_column_name(column)}::text), 1, 16))::bit(64)::bigint)", { table_name: table_name }])))

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
      # @!method joins_advisory_locks(column: _advisory_lockable_column)
      # @!scope class
      # @param column [String, Symbol] column values to Advisory Lock against
      # @return [ActiveRecord::Relation]
      # @example Get the records that have a session awaiting a lock:
      #   MyLockableRecord.joins_advisory_locks.where("pg_locks.granted = ?", false)
      scope :joins_advisory_locks, (lambda do |column: _advisory_lockable_column|
        join_sql = <<~SQL.squish
          LEFT JOIN pg_locks ON pg_locks.locktype = 'advisory'
            AND pg_locks.objsubid = 1
            AND pg_locks.classid = ('x' || substr(md5(:table_name || '-' || #{quoted_table_name}.#{connection.quote_column_name(column)}::text), 1, 16))::bit(32)::int
            AND pg_locks.objid = (('x' || substr(md5(:table_name || '-' || #{quoted_table_name}.#{connection.quote_column_name(column)}::text), 1, 16))::bit(64) << 32)::bit(32)::int
        SQL

        joins(sanitize_sql_for_conditions([join_sql, { table_name: table_name }]))
      end)

      # Find records that do not have an advisory lock on them.
      # @!method advisory_unlocked(column: _advisory_lockable_column)
      # @!scope class
      # @param column [String, Symbol] column values to Advisory Lock against
      # @return [ActiveRecord::Relation]
      scope :advisory_unlocked, ->(column: _advisory_lockable_column) { joins_advisory_locks(column: column).where(pg_locks: { locktype: nil }) }

      # Find records that have an advisory lock on them.
      # @!method advisory_locked(column: _advisory_lockable_column)
      # @!scope class
      # @param column [String, Symbol] column values to Advisory Lock against
      # @return [ActiveRecord::Relation]
      scope :advisory_locked, ->(column: _advisory_lockable_column) { joins_advisory_locks(column: column).where.not(pg_locks: { locktype: nil }) }

      # Find records with advisory locks owned by the current Postgres
      # session/connection.
      # @!method advisory_locked(column: _advisory_lockable_column)
      # @!scope class
      # @param column [String, Symbol] column values to Advisory Lock against
      # @return [ActiveRecord::Relation]
      scope :owns_advisory_locked, ->(column: _advisory_lockable_column) { joins_advisory_locks(column: column).where('"pg_locks"."pid" = pg_backend_pid()') }

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
      # @param column [String, Symbol]  name of advisory lock or unlock function
      # @param function [String, Symbol] Postgres Advisory Lock function name to use
      # @param unlock_session [Boolean] Whether to unlock all advisory locks in the session afterwards
      # @yield [Array<Lockable>] the records that were successfully locked.
      # @return [Object] the result of the block.
      #
      # @example Work on the first two +MyLockableRecord+ objects that could be locked:
      #   MyLockableRecord.order(created_at: :asc).limit(2).with_advisory_lock do |record|
      #     do_something_with record
      #   end
      def with_advisory_lock(key: nil, column: _advisory_lockable_column, function: advisory_lockable_function, unlock_session: false)
        raise ArgumentError, "Must provide a block" unless block_given?

        records = if key
                    advisory_record_lock!(key: key, function: function)
                  else
                    advisory_lock(column: column, function: function).to_a
                  end

        begin
          unscoped { yield(records) }
        ensure
          if unlock_session
            advisory_unlock_session
          elsif key
            advisory_record_unlock(key: key, function: advisory_unlockable_function(function)) unless $ERROR_INFO.is_a? RecordAlreadyAdvisoryLockedError
          else
            records.each do |record|
              record.advisory_unlock(key: record.lockable_column_key(column: column), function: advisory_unlockable_function(function))
            end
          end
        end
      end

      # Acquires an advisory lock on this record or raises
      # {RecordAlreadyAdvisoryLockedError} if it is already locked by another
      # database session.
      # @param key [String, Symbol] Key to lock against
      # @param function [String, Symbol] Postgres Advisory Lock function name to use
      # @raise [RecordAlreadyAdvisoryLockedError]
      # @return [Boolean] +true+
      def advisory_record_lock!(key:, function: advisory_lockable_function)
        result = advisory_record_lock(key: key, function: function)
        result || raise(RecordAlreadyAdvisoryLockedError)
      end

      # Acquires an advisory lock on this record if it is not already locked by
      # another database session. Be careful to ensure you release the lock when
      # you are done with {#advisory_record_unlock} to release all remaining locks.
      # @param key [String, Symbol] Key to Advisory Lock against
      # @param function [String, Symbol] Postgres Advisory Lock function name to use
      # @return [Boolean] whether the lock was acquired.
      def advisory_record_lock(key:, function: advisory_lockable_function)
        query = if function.include? "_try_"
                  <<~SQL.squish
                    SELECT #{function}(('x'||substr(md5($1::text), 1, 16))::bit(64)::bigint) AS locked
                  SQL
                else
                  <<~SQL.squish
                    SELECT #{function}(('x'||substr(md5($1::text), 1, 16))::bit(64)::bigint)::text AS locked
                  SQL
                end

        binds = [
          ActiveRecord::Relation::QueryAttribute.new('key', key, ActiveRecord::Type::String.new),
        ]
        connection.exec_query(pg_or_jdbc_query(query), 'GoodJob::Lockable Advisory Lock', binds).first['locked']
      end

      # Releases an advisory lock on this record if it is locked by this database
      # session. Note that advisory locks stack, so you must call
      # {#advisory_unlock} and {#advisory_lock} the same number of times.
      # @param key [String, Symbol] Key to lock against
      # @param function [String, Symbol] Postgres Advisory Lock function name to use
      # @return [Boolean] whether the lock was released.
      def advisory_record_unlock(key:, function: advisory_unlockable_function)
        query = <<~SQL.squish
          SELECT #{function}(('x'||substr(md5($1::text), 1, 16))::bit(64)::bigint) AS unlocked
        SQL
        binds = [
          ActiveRecord::Relation::QueryAttribute.new('key', key, ActiveRecord::Type::String.new),
        ]
        connection.exec_query(pg_or_jdbc_query(query), 'GoodJob::Lockable Advisory Unlock', binds).first['unlocked']
      end

      def _advisory_lockable_column
        advisory_lockable_column || primary_key
      end

      def supports_cte_materialization_specifiers?
        return @_supports_cte_materialization_specifiers if defined?(@_supports_cte_materialization_specifiers)

        @_supports_cte_materialization_specifiers = connection.postgresql_version >= 120000
      end

      # Postgres advisory unlocking function for the class
      # @param function [String, Symbol] name of advisory lock or unlock function
      # @return [Boolean]
      def advisory_unlockable_function(function = advisory_lockable_function)
        function.to_s.sub("_lock", "_unlock").sub("_try_", "_")
      end

      # Unlocks all advisory locks active in the current database session/connection
      # @return [void]
      def advisory_unlock_session
        connection.exec_query("SELECT pg_advisory_unlock_all()::text AS unlocked", 'GoodJob::Lockable Unlock Session').first[:unlocked]
      end

      # Converts SQL query strings between PG-compatible and JDBC-compatible syntax
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

    # Acquires an advisory lock on this record if it is not already locked by
    # another database session. Be careful to ensure you release the lock when
    # you are done with {#advisory_unlock} (or {#advisory_unlock!} to release
    # all remaining locks).
    # @param key [String, Symbol] Key to Advisory Lock against
    # @param function [String, Symbol] Postgres Advisory Lock function name to use
    # @return [Boolean] whether the lock was acquired.
    def advisory_lock(key: lockable_key, function: advisory_lockable_function)
      self.class.advisory_record_lock(key: key, function: function)
    end

    # Releases an advisory lock on this record if it is locked by this database
    # session. Note that advisory locks stack, so you must call
    # {#advisory_unlock} and {#advisory_lock} the same number of times.
    # @param key [String, Symbol] Key to lock against
    # @param function [String, Symbol] Postgres Advisory Lock function name to use
    # @return [Boolean] whether the lock was released.
    def advisory_unlock(key: lockable_key, function: self.class.advisory_unlockable_function(advisory_lockable_function))
      self.class.advisory_record_unlock(key: key, function: function)
    end

    # Acquires an advisory lock on this record or raises
    # {RecordAlreadyAdvisoryLockedError} if it is already locked by another
    # database session.
    # @param key [String, Symbol] Key to lock against
    # @param function [String, Symbol] Postgres Advisory Lock function name to use
    # @raise [RecordAlreadyAdvisoryLockedError]
    # @return [Boolean] +true+
    def advisory_lock!(key: lockable_key, function: advisory_lockable_function)
      self.class.advisory_record_lock!(key: key, function: function)
    end

    # Acquires an advisory lock on this record and safely releases it after the
    # passed block is completed. If the record is locked by another database
    # session, this raises {RecordAlreadyAdvisoryLockedError}.
    # @param key [String, Symbol] Key to lock against
    # @param function [String, Symbol] Postgres Advisory Lock function name to use
    # @yield Nothing
    # @return [Object] The result of the block.
    #
    # @example
    #   record = MyLockableRecord.first
    #   record.with_advisory_lock do
    #     do_something_with record
    #   end
    def with_advisory_lock(key: lockable_key, function: advisory_lockable_function)
      raise ArgumentError, "Must provide a block" unless block_given?

      advisory_lock!(key: key, function: function)
      yield
    ensure
      advisory_unlock(key: key, function: self.class.advisory_unlockable_function(function)) unless $ERROR_INFO.is_a? RecordAlreadyAdvisoryLockedError
    end

    # Tests whether this record has an advisory lock on it.
    # @param key [String, Symbol] Key to test lock against
    # @return [Boolean]
    def advisory_locked?(key: lockable_key)
      query = <<~SQL.squish
        SELECT 1 AS one
        FROM pg_locks
        WHERE pg_locks.locktype = 'advisory'
          AND pg_locks.objsubid = 1
          AND pg_locks.classid = ('x' || substr(md5($1::text), 1, 16))::bit(32)::int
          AND pg_locks.objid = (('x' || substr(md5($2::text), 1, 16))::bit(64) << 32)::bit(32)::int
      SQL
      binds = [
        ActiveRecord::Relation::QueryAttribute.new('key', key, ActiveRecord::Type::String.new),
        ActiveRecord::Relation::QueryAttribute.new('key', key, ActiveRecord::Type::String.new),
      ]
      self.class.connection.exec_query(pg_or_jdbc_query(query), 'GoodJob::Lockable Advisory Locked?', binds).any?
    end

    # Tests whether this record does not have an advisory lock on it.
    # @param key [String, Symbol] Key to test lock against
    # @return [Boolean]
    def advisory_unlocked?(key: lockable_key)
      !advisory_locked?(key: key)
    end

    # Tests whether this record is locked by the current database session.
    # @param key [String, Symbol] Key to test lock against
    # @return [Boolean]
    def owns_advisory_lock?(key: lockable_key)
      query = <<~SQL.squish
        SELECT 1 AS one
        FROM pg_locks
        WHERE pg_locks.locktype = 'advisory'
          AND pg_locks.objsubid = 1
          AND pg_locks.classid = ('x' || substr(md5($1::text), 1, 16))::bit(32)::int
          AND pg_locks.objid = (('x' || substr(md5($2::text), 1, 16))::bit(64) << 32)::bit(32)::int
          AND pg_locks.pid = pg_backend_pid()
      SQL
      binds = [
        ActiveRecord::Relation::QueryAttribute.new('key', key, ActiveRecord::Type::String.new),
        ActiveRecord::Relation::QueryAttribute.new('key', key, ActiveRecord::Type::String.new),
      ]
      self.class.connection.exec_query(pg_or_jdbc_query(query), 'GoodJob::Lockable Owns Advisory Lock?', binds).any?
    end

    # Releases all advisory locks on the record that are held by the current
    # database session.
    # @param key [String, Symbol] Key to lock against
    # @param function [String, Symbol] Postgres Advisory Lock function name to use
    # @return [void]
    def advisory_unlock!(key: lockable_key, function: self.class.advisory_unlockable_function(advisory_lockable_function))
      advisory_unlock(key: key, function: function) while advisory_locked?
    end

    # Default Advisory Lock key
    # @return [String]
    def lockable_key
      lockable_column_key
    end

    # Default Advisory Lock key for column-based locking
    # @return [String]
    def lockable_column_key(column: self.class._advisory_lockable_column)
      "#{self.class.table_name}-#{self[column]}"
    end

    delegate :pg_or_jdbc_query, to: :class
  end
end
