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
  module AdvisoryLockable
    extend ActiveSupport::Concern

    # Indicates an advisory lock is already held on a record by another
    # database session.
    RecordAlreadyAdvisoryLockedError = Class.new(StandardError)

    # Global hash function used to convert advisory lock key strings to bigints.
    # Defaults to "md5", which requires no PostgreSQL extensions.
    # Alternative sha* functions (e.g. "sha256") require the pgcrypto extension.
    # See +advisory_lock_bigint_sql+ for details on how this value is used.
    #
    # @example
    #   GoodJob::AdvisoryLockable.hash_function = "sha256"
    class << self
      attr_writer :hash_function

      def hash_function
        @hash_function ||= "md5"
      end
    end

    included do
      # Default column to be used when creating Advisory Locks
      class_attribute :advisory_lockable_column, instance_accessor: false, default: nil

      # Default Postgres function to be used for Advisory Locks
      class_attribute :advisory_lockable_function, default: "pg_try_advisory_lock"

      # Rails < 7.2 does not have lease_connection as a class method.
      define_singleton_method(:lease_connection) { connection } unless respond_to?(:lease_connection)

      # Rails < 7.2 does not have adapter_class as a class method, and adapter
      # quoting methods (quote_table_name, quote_column_name) are instance-only.
      # Provide a proxy that responds to those methods by delegating to a connection.
      unless respond_to?(:adapter_class)
        define_singleton_method(:adapter_class) do
          @_adapter_class ||= begin
            pool = connection_pool
            proxy = Object.new
            proxy.define_singleton_method(:quote_table_name) { |name| pool.with_connection { |c| c.quote_table_name(name) } }
            proxy.define_singleton_method(:quote_column_name) { |name| pool.with_connection { |c| c.quote_column_name(name) } }
            proxy
          end
        end
      end

      # Attempt to acquire an advisory lock on the selected records and
      # return only those records for which a lock could be acquired.
      # @!method advisory_lock(column: _advisory_lockable_column, function: advisory_lockable_function)
      # @!scope class
      # @param column [String, Symbol] column values to Advisory Lock against
      # @param function [String, Symbol]  Postgres Advisory Lock function name to use
      # @return [ActiveRecord::Relation]
      #   A relation selecting only the records that were locked.
      scope :advisory_lock, (lambda do |column: _advisory_lockable_column, function: advisory_lockable_function, select_limit: nil, connection: nil|
        connection || lease_connection # ensure a sticky connection; advisory locks are session-scoped and must outlive this query
        original_query = self

        primary_key_for_select = primary_key.to_sym
        column_for_select = column.to_sym

        cte_table = Arel::Table.new(:rows)
        cte_query = original_query.except(:limit)
        cte_query = if primary_key_for_select == column_for_select
                      cte_query.select(primary_key_for_select)
                    else
                      cte_query.select(primary_key_for_select, column_for_select)
                    end
        cte_query = cte_query.limit(select_limit) if select_limit
        cte_type = supports_cte_materialization_specifiers? ? :MATERIALIZED : :""
        composed_cte = Arel::Nodes::As.new(cte_table, Arel::Nodes::UnaryOperation.new(cte_type, cte_query.arel))

        lock_condition = "#{function}(#{advisory_lock_bigint_sql("#{_quoted_table_name_string} || '-' || #{adapter_class.quote_table_name(cte_table.name)}.#{adapter_class.quote_column_name(column)}::text")})"
        query = cte_table.project(cte_table[:id])
                  .with(composed_cte)
                  .where(defined?(Arel::Nodes::BoundSqlLiteral) ? Arel::Nodes::BoundSqlLiteral.new(lock_condition, [], {}) : Arel::Nodes::SqlLiteral.new(lock_condition))

        limit = original_query.arel.ast.limit
        query.limit = limit.value if limit.present?

        # Arel.sql and the IN clause prevent this from being preparable
        # That's why this is manually composed of BoundSqlLiteral's and an InfixOperation
        # to sidestep anywhere in Arel where the `collector.preparable = false` is set
        unscoped.where(Arel::Nodes::InfixOperation.new("IN", arel_table[primary_key], query)).merge(original_query.only(:order))
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
        quoted_column = adapter_class.quote_column_name(column)
        joins(<<~SQL.squish)
          LEFT JOIN pg_locks ON pg_locks.locktype = 'advisory'
            AND pg_locks.objsubid = 1
            AND pg_locks.classid = #{advisory_lock_classid_sql("#{_quoted_table_name_string} || '-' || #{quoted_table_name}.#{quoted_column}::text")}
            AND pg_locks.objid = #{advisory_lock_objid_sql("#{_quoted_table_name_string} || '-' || #{quoted_table_name}.#{quoted_column}::text")}
        SQL
      end)

      # Joins the current query with Postgres's +pg_locks+ table AND SELECTs the resulting columns
      # @!method joins_advisory_locks(column: _advisory_lockable_column)
      # @!scope class
      # @param column [String, Symbol] column values to Advisory Lock against
      # @return [ActiveRecord::Relation]
      scope :includes_advisory_locks, (lambda do |column: _advisory_lockable_column|
        owns_advisory_lock_sql = "#{adapter_class.quote_table_name('pg_locks')}.#{adapter_class.quote_column_name('pid')} = pg_backend_pid() AS owns_advisory_lock"
        joins_advisory_locks(column: column).select("#{quoted_table_name}.*, #{adapter_class.quote_table_name('pg_locks')}.locktype, #{owns_advisory_lock_sql}")
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

      after_create lambda {
        advisory_lock || begin
          errors.add(self.class._advisory_lockable_column, "Failed to acquire advisory lock: #{lockable_key}")
          raise ActiveRecord::RecordInvalid # do not reference the record because it can cause I18n missing translation error
        end
      }, if: :create_with_advisory_lock
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
      # If the Active Record Relation has WHERE conditions that have the potential
      # to be updated/changed elsewhere, be sure to verify the conditions are still
      # satisfied, or check the lock status, as an unlocked and out-of-date record could be returned.
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
      def with_advisory_lock(column: _advisory_lockable_column, function: advisory_lockable_function, unlock_session: false, select_limit: nil)
        raise ArgumentError, "Must provide a block" unless block_given?

        connection_pool.with_connection do |conn|
          records = advisory_lock(column: column, function: function, select_limit: select_limit, connection: conn).to_a

          begin
            unscoped { yield(records) }
          ensure
            if unlock_session
              advisory_unlock_session(connection: conn)
            else
              unlock_function = advisory_unlockable_function(function)
              if unlock_function
                records.each do |record|
                  record.advisory_unlock(key: record.lockable_column_key(column: column), function: unlock_function, connection: conn)
                end
              end
            end
          end
        end
      end

      # Acquires an advisory lock on this record if it is not already locked by
      # another database session. Be careful to ensure you release the lock when
      # you are done with {#advisory_unlock_key} to release all remaining locks.
      # @param key [String, Symbol] Key to Advisory Lock against
      # @param function [String, Symbol] Postgres Advisory Lock function name to use
      # @return [Boolean] whether the lock was acquired.
      def advisory_lock_key(key, function: advisory_lockable_function, connection: nil)
        query = if function.include? "_try_"
                  <<~SQL.squish
                    SELECT #{function}(#{advisory_lock_bigint_sql('$1::text')}) AS locked
                  SQL
                else
                  <<~SQL.squish
                    SELECT #{function}(#{advisory_lock_bigint_sql('$1::text')})::text AS locked
                  SQL
                end

        binds = [
          ActiveRecord::Relation::QueryAttribute.new('key', key, ActiveRecord::Type::String.new),
        ]

        if block_given?
          connection_pool.with_connection do |conn|
            locked = conn.exec_query(pg_or_jdbc_query(query), 'GoodJob::Lockable Advisory Lock', binds).first['locked']
            return nil unless locked

            begin
              yield
            ensure
              unlock_function = advisory_unlockable_function(function)
              advisory_unlock_key(key, function: unlock_function, connection: conn) if unlock_function
            end
          end
        else
          (connection || lease_connection).exec_query(pg_or_jdbc_query(query), 'GoodJob::Lockable Advisory Lock', binds).first['locked']
        end
      end

      # Releases an advisory lock on this record if it is locked by this database
      # session. Note that advisory locks stack, so you must call
      # {#advisory_unlock} and {#advisory_lock} the same number of times.
      # @param key [String, Symbol] Key to lock against
      # @param function [String, Symbol] Postgres Advisory Lock function name to use
      # @return [Boolean] whether the lock was released.
      def advisory_unlock_key(key, function: advisory_unlockable_function, connection: nil)
        raise ArgumentError, "Cannot unlock transactional locks" if function.include? "_xact_"
        raise ArgumentError, "No unlock function provide" if function.blank?

        query = <<~SQL.squish
          SELECT #{function}(#{advisory_lock_bigint_sql('$1::text')}) AS unlocked
        SQL
        binds = [
          ActiveRecord::Relation::QueryAttribute.new('key', key, ActiveRecord::Type::String.new),
        ]
        (connection || lease_connection).exec_query(pg_or_jdbc_query(query), 'GoodJob::Lockable Advisory Unlock', binds).first['unlocked']
      end

      # Tests whether the provided key has an advisory lock on it.
      # @param key [String, Symbol] Key to test lock against
      # @return [Boolean]
      def advisory_locked_key?(key)
        query = <<~SQL.squish
          SELECT 1 AS one
          FROM pg_locks
          WHERE pg_locks.locktype = 'advisory'
            AND pg_locks.objsubid = 1
            AND pg_locks.classid = #{advisory_lock_classid_sql('$1::text')}
            AND pg_locks.objid = #{advisory_lock_objid_sql('$2::text')}
          LIMIT 1
        SQL
        binds = [
          ActiveRecord::Relation::QueryAttribute.new('key', key, ActiveRecord::Type::String.new),
          ActiveRecord::Relation::QueryAttribute.new('key', key, ActiveRecord::Type::String.new),
        ]
        connection_pool.with_connection { |conn| conn.exec_query(pg_or_jdbc_query(query), 'GoodJob::Lockable Advisory Locked?', binds).any? }
      end

      # Tests whether this record is locked by the current database session.
      # @param key [String, Symbol] Key to test lock against
      # @return [Boolean]
      def owns_advisory_lock_key?(key)
        query = <<~SQL.squish
          SELECT 1 AS one
          FROM pg_locks
          WHERE pg_locks.locktype = 'advisory'
            AND pg_locks.objsubid = 1
            AND pg_locks.classid = #{advisory_lock_classid_sql('$1::text')}
            AND pg_locks.objid = #{advisory_lock_objid_sql('$2::text')}
            AND pg_locks.pid = pg_backend_pid()
          LIMIT 1
        SQL
        binds = [
          ActiveRecord::Relation::QueryAttribute.new('key', key, ActiveRecord::Type::String.new),
          ActiveRecord::Relation::QueryAttribute.new('key', key, ActiveRecord::Type::String.new),
        ]
        lease_connection.exec_query(pg_or_jdbc_query(query), 'GoodJob::Lockable Owns Advisory Lock?', binds).any?
      end

      def _advisory_lockable_column
        advisory_lockable_column || primary_key
      end

      # Converts a SQL string expression to a 64-bit integer (bigint) for use as
      # a Postgres advisory lock key.
      #
      # By default uses md5 to hash the string to a 128-bit digest, then takes the
      # first 64 bits as a bigint. md5 is used for its wide availability (no
      # PostgreSQL extensions required) and good bit distribution—not for any
      # cryptographic property.
      #
      # The hash function can be configured globally via +GoodJob::GoodJob::AdvisoryLockable.hash_function=+.
      # - "md5" (default): no extensions required.
      # - "hashtext": PostgreSQL's internal 32-bit hash; no extensions required.
      # - "uuid_v5": requires the uuid-ossp extension.
      # - sha* (e.g. "sha256"): requires the pgcrypto extension.
      def advisory_lock_bigint_sql(value_sql)
        case GoodJob::AdvisoryLockable.hash_function.to_s.downcase
        when "md5"
          # md5 produces 32 hex chars; take first 16 (64 bits) and interpret as bigint
          "('x' || substr(md5(#{value_sql}), 1, 16))::bit(64)::bigint"
        when "hashtext"
          # hashtext is PostgreSQL's internal non-cryptographic 32-bit hash function,
          # cast to bigint for use as a 64-bit advisory lock key
          "hashtext((#{value_sql})::text)::bigint"
        when "uuid_v5"
          # uuid_generate_v5 hashes the input with a namespace UUID using SHA-1.
          # The DNS namespace UUID (6ba7b810-9dad-11d1-80b4-00c04fd430c8) is a stable
          # constant defined by RFC 4122. Requires the uuid-ossp extension.
          "('x' || substr(replace(uuid_generate_v5('6ba7b810-9dad-11d1-80b4-00c04fd430c8'::uuid, (#{value_sql})::text)::text, '-', ''), 1, 16))::bit(64)::bigint"
        else
          # pgcrypto's digest() supports sha1, sha224, sha256, sha384, sha512
          "('x' || substr(encode(digest((#{value_sql})::text, '#{GoodJob::AdvisoryLockable.hash_function}'), 'hex'), 1, 16))::bit(64)::bigint"
        end
      end

      # Extracts the upper 32 bits of the advisory lock bigint, used as +classid+ in pg_locks.
      def advisory_lock_classid_sql(value_sql)
        "substring((#{advisory_lock_bigint_sql(value_sql)})::bit(64) from 1 for 32)::bit(32)::int"
      end

      # Extracts the lower 32 bits of the advisory lock bigint, used as +objid+ in pg_locks.
      def advisory_lock_objid_sql(value_sql)
        "substring((#{advisory_lock_bigint_sql(value_sql)})::bit(64) from 33 for 32)::bit(32)::int"
      end

      def _quoted_table_name_string
        @_quoted_table_name_string ||= "'#{table_name.gsub("'", "''")}'"
      end

      def supports_cte_materialization_specifiers?
        return @_supports_cte_materialization_specifiers if defined?(@_supports_cte_materialization_specifiers)

        @_supports_cte_materialization_specifiers = connection_pool.with_connection { |conn| conn.postgresql_version >= 120000 }
      end

      # Postgres advisory unlocking function for the class
      # @param function [String, Symbol] name of advisory lock or unlock function
      # @return [Boolean]
      def advisory_unlockable_function(function = advisory_lockable_function)
        return nil if function.include? "_xact_" # Cannot unlock transactional locks

        function.to_s.sub("_lock", "_unlock").sub("_try_", "_")
      end

      # Unlocks all advisory locks active in the current database session/connection
      # @return [void]
      def advisory_unlock_session(connection: nil)
        (connection || lease_connection).exec_query("SELECT pg_advisory_unlock_all()::text AS unlocked", 'GoodJob::Lockable Unlock Session').first[:unlocked]
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
    def advisory_lock(key: lockable_key, function: advisory_lockable_function, connection: nil)
      self.class.advisory_lock_key(key, function: function, connection: connection)
    end

    # Releases an advisory lock on this record if it is locked by this database
    # session. Note that advisory locks stack, so you must call
    # {#advisory_unlock} and {#advisory_lock} the same number of times.
    # @param key [String, Symbol] Key to lock against
    # @param function [String, Symbol] Postgres Advisory Lock function name to use
    # @return [Boolean] whether the lock was released.
    def advisory_unlock(key: lockable_key, function: self.class.advisory_unlockable_function(advisory_lockable_function), connection: nil)
      self.class.advisory_unlock_key(key, function: function, connection: connection)
    end

    # Acquires an advisory lock on this record or raises
    # {RecordAlreadyAdvisoryLockedError} if it is already locked by another
    # database session.
    # @param key [String, Symbol] Key to lock against
    # @param function [String, Symbol] Postgres Advisory Lock function name to use
    # @raise [RecordAlreadyAdvisoryLockedError]
    # @return [Boolean] +true+
    def advisory_lock!(key: lockable_key, function: advisory_lockable_function, connection: nil)
      advisory_lock(key: key, function: function, connection: connection) || raise(RecordAlreadyAdvisoryLockedError)
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

      self.class.connection_pool.with_connection do |conn|
        advisory_lock!(key: key, function: function, connection: conn)
        begin
          yield
        ensure
          unlock_function = self.class.advisory_unlockable_function(function)
          advisory_unlock(key: key, function: unlock_function, connection: conn) if unlock_function
        end
      end
    end

    # Tests whether this record has an advisory lock on it.
    # @param key [String, Symbol] Key to test lock against
    # @return [Boolean]
    def advisory_locked?(key: lockable_key)
      self.class.advisory_locked_key?(key)
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
      self.class.owns_advisory_lock_key?(key)
    end

    # Releases all advisory locks on the record that are held by the current
    # database session.
    # @param key [String, Symbol] Key to lock against
    # @param function [String, Symbol] Postgres Advisory Lock function name to use
    # @return [void]
    def advisory_unlock!(key: lockable_key, function: self.class.advisory_unlockable_function)
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
