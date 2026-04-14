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

    # Tracks advisory lock counts per connection per key for two purposes:
    #
    # 1. CTE phantom cleanup: The CTE-based locking query can sometimes
    #    have pg_try_advisory_lock evaluated more than once for the same
    #    row by the query planner, creating phantom re-entrant session
    #    locks. When a key has been CTE-locked, the final unlock uses
    #    advisory_unlock_key! to fully release any phantoms.
    #
    # 2. Xact lock awareness: Transaction-scoped locks (+pg_advisory_xact_lock+)
    #    are tracked because pg_locks cannot distinguish them from session
    #    locks. When an xact lock is active on the same key,
    #    advisory_unlock_key! cannot be used (it would loop forever), so
    #    cleanup falls back to looping pg_advisory_unlock until it returns
    #    false. Xact counts are pruned when no transaction is open on
    #    the connection (since xact locks release at the outermost COMMIT,
    #    not at savepoint release).
    #
    # Thread safety: a leased connection is only ever accessed by the
    # thread that leased it, so per-connection bookkeeping does not
    # require additional synchronization.
    #
    # Per-key structure: [session_count, xact_txns, cte]
    #   xact_txns: Array of WeakRefs to AR transaction objects
    class AdvisoryLockCounter
      def initialize
        if defined?(ObjectSpace::WeakKeyMap)
          # WeakKeyMap (Ruby 3.3+) holds weak keys with strong values:
          # entries are automatically removed when the connection is GC'd.
          @map = ObjectSpace::WeakKeyMap.new
          @use_object_id = false
        else
          # On older Rubies, key by object_id with a WeakRef to the
          # connection stored alongside the data. Stale entries (where
          # the WeakRef is dead) are pruned on every access.
          @map = {}
          @use_object_id = true
        end
      end

      def [](conn)
        if @use_object_id
          entry = @map[oid(conn)]
          return unless entry

          ref, counts = entry
          return counts if ref.weakref_alive? && ref.__getobj__.equal?(conn)

          @map.delete(oid(conn))
          nil
        else
          @map[conn]
        end
      end

      def []=(conn, value)
        if @use_object_id
          @map[oid(conn)] = [WeakRef.new(conn), value]
        else
          @map[conn] = value
        end
      end

      def delete(conn)
        if @use_object_id
          @map.delete(oid(conn))
          prune_stale_entries
        else
          @map.delete(conn)
        end
      end

      # Clear session-level lock bookkeeping for a connection, preserving
      # any active transaction-scoped lock entries.
      def clear_session_locks(conn)
        counts = self[conn]
        return unless counts

        counts.each do |key, (_session_count, xact_txns, _cte)|
          if xact_txns.empty?
            counts.delete(key)
          else
            counts[key] = [0, xact_txns, false]
          end
        end
      end

      private

      def oid(conn) = conn.object_id

      def prune_stale_entries
        return unless @use_object_id

        @map.delete_if do |_oid, (ref, _counts)|
          !ref.weakref_alive?
        rescue WeakRef::RefError
          true
        end
      end

      public

      # Record a lock acquisition.
      # Per-key structure: [session_count, xact_txns, cte]
      #   xact_txns is an Array of WeakRefs to transaction objects
      def record_lock(conn, key, cte: false, xact: false)
        prune(conn)
        counts = self[conn] || (self[conn] = {})
        session_count, xact_txns, was_cte = counts[key] || [0, [], false]
        if xact
          xact_txns += [WeakRef.new(conn.current_transaction)]
        else
          session_count += 1
        end
        counts[key] = [session_count, xact_txns, was_cte || cte]
      end

      # Record a lock release (session-level only; xact locks cannot be
      # manually unlocked). Returns [new_session_count, active_xact_count, cte].
      def record_unlock(conn, key)
        prune(conn)
        counts = self[conn]
        return [0, 0, false] unless counts

        session_count, xact_txns, cte = counts[key] || [0, [], false]
        new_session_count = [session_count - 1, 0].max
        if new_session_count.zero? && xact_txns.empty?
          counts.delete(key)
        else
          counts[key] = [new_session_count, xact_txns, cte]
        end
        [new_session_count, xact_txns.size, cte]
      end

      # Returns [session_count, active_xact_count, cte] for a specific key.
      def counts_for(conn, key)
        prune(conn)
        entry = self[conn]&.dig(key)
        return [0, 0, false] unless entry

        session_count, xact_txns, cte = entry
        [session_count, xact_txns.size, cte]
      end

      # Remove xact entries whose transactions are no longer open
      # (committed, rolled back, or GC'd).
      def prune(conn)
        counts = self[conn]
        return unless counts

        counts.each do |key, (session_count, xact_txns, cte)|
          live_txns = xact_txns.select do |ref|
            ref.weakref_alive? && ref.open?
          rescue WeakRef::RefError
            false
          end

          if session_count.zero? && live_txns.empty?
            counts.delete(key)
          elsif live_txns.size != xact_txns.size
            counts[key] = [session_count, live_txns, cte]
          end
        end
      end
    end

    ADVISORY_LOCK_COUNTS = AdvisoryLockCounter.new

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
            AND pg_locks.classid = ('x' || substr(md5(#{_quoted_table_name_string} || '-' || #{quoted_table_name}.#{quoted_column}::text), 1, 16))::bit(32)::int
            AND pg_locks.objid = (('x' || substr(md5(#{_quoted_table_name_string} || '-' || #{quoted_table_name}.#{quoted_column}::text), 1, 16))::bit(64) << 32)::bit(32)::int
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
      # Acquires advisory locks on the selected records via a CTE query
      # with +pg_try_advisory_lock+ in the WHERE clause.
      #
      # Without a block, returns an ActiveRecord::Relation of the locked records.
      # The caller is responsible for releasing the locks.
      #
      # With a block, locks the records, yields them, and releases the locks
      # when the block completes (like the previous +with_advisory_lock+).
      #
      # @param column [String, Symbol] column values to Advisory Lock against
      # @param function [String, Symbol] Postgres Advisory Lock function name to use
      # @param select_limit [Integer, nil] limit on candidates to attempt locking
      # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter, nil]
      # @param unlock_session [Boolean] Whether to unlock all advisory locks in the session afterwards (block form only)
      # @yield [Array<Lockable>] the records that were successfully locked.
      # @return [ActiveRecord::Relation, Object] the relation (no block) or the block result.
      def advisory_lock(column: _advisory_lockable_column, function: advisory_lockable_function, select_limit: nil, connection: nil, unlock_session: false, &block)
        if block
          connection_pool.with_connection do |conn|
            records = advisory_lock(column: column, function: function, select_limit: select_limit, connection: conn).to_a
            records.each { |record| record_advisory_lock(conn, record.lockable_column_key(column: column), cte: true) }

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
        else
          connection || lease_connection # ensure a sticky connection; advisory locks are session-scoped and must outlive this query
          original_query = all

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

          lock_condition = "#{function}(('x' || substr(md5(#{_quoted_table_name_string} || '-' || #{adapter_class.quote_table_name(cte_table.name)}.#{adapter_class.quote_column_name(column)}::text), 1, 16))::bit(64)::bigint)"
          query = cte_table.project(cte_table[:id])
                           .with(composed_cte)
                           .where(defined?(Arel::Nodes::BoundSqlLiteral) ? Arel::Nodes::BoundSqlLiteral.new(lock_condition, [], {}) : Arel::Nodes::SqlLiteral.new(lock_condition))

          limit = original_query.arel.ast.limit
          query.limit = limit.value if limit.present?

          unscoped.where(Arel::Nodes::InfixOperation.new("IN", arel_table[primary_key], query)).merge(original_query.only(:order))
        end
      end

      # @deprecated Use {.advisory_lock} with a block instead.
      def with_advisory_lock(**kwargs, &block)
        raise ArgumentError, "Must provide a block" unless block

        advisory_lock(**kwargs, &block)
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

        xact = function.include?("_xact_")

        if block_given?
          connection_pool.with_connection do |conn|
            locked = conn.exec_query(pg_or_jdbc_query(query), 'GoodJob::Lockable Advisory Lock', binds).first['locked']
            return nil unless locked

            record_advisory_lock(conn, key, xact: xact)

            begin
              yield
            ensure
              unlock_function = advisory_unlockable_function(function)
              _advisory_unlock_key_once(key, function: unlock_function, connection: conn) if unlock_function
            end
          end
        else
          conn = connection || lease_connection
          result = conn.exec_query(pg_or_jdbc_query(query), 'GoodJob::Lockable Advisory Lock', binds).first['locked']
          record_advisory_lock(conn, key, xact: xact) if result
          result
        end
      end

      # Releases an advisory lock on this record if it is locked by this database
      # session. Note that advisory locks stack, so you must call
      # {#advisory_unlock} and {#advisory_lock} the same number of times.
      #
      # When the bookkeeping indicates this is the final session unlock for a
      # CTE-acquired lock, delegates to {.advisory_unlock_key!} to fully release
      # any phantom re-entrant locks from the query planner.
      #
      # @param key [String, Symbol] Key to lock against
      # @param function [String, Symbol] Postgres Advisory Lock function name to use
      # @return [Boolean] whether the lock was released.
      def advisory_unlock_key(key, function: advisory_unlockable_function, connection: nil)
        conn = connection || lease_connection
        session_count, _xact_count, cte = ADVISORY_LOCK_COUNTS.counts_for(conn, key)

        if session_count <= 1 && cte
          advisory_unlock_key!(key, function: function, connection: conn)
        else
          _advisory_unlock_key_once(key, function: function, connection: conn)
        end
      end

      # Releases all advisory locks for the given key held by the current
      # database session, calling pg_advisory_unlock until the lock is fully
      # released. Uses bookkeeping to choose the right strategy:
      #
      # - When an xact lock is also held on the same key, +owns_advisory_lock_key?+
      #   would always return true (pg_locks cannot distinguish session vs xact locks),
      #   so instead it loops +pg_advisory_unlock+ until it returns false. The final
      #   call that hits the xact lock will return false and generate a Postgres
      #   WARNING; this is unavoidable.
      # - Otherwise, loops while +owns_advisory_lock_key?+ to safely release all
      #   session-level re-entrant locks.
      #
      # @param key [String, Symbol] Key to unlock
      # @param function [String, Symbol] Postgres Advisory Lock function name to use
      # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter, nil]
      # @return [void]
      def advisory_unlock_key!(key, function: advisory_unlockable_function, connection: nil)
        conn = connection || lease_connection
        _, xact_count, = ADVISORY_LOCK_COUNTS.counts_for(conn, key)

        if xact_count.positive?
          # An active xact lock on the same key means owns_advisory_lock_key? will
          # always return true. Loop pg_advisory_unlock until it returns false.
          nil while _advisory_unlock_key_once(key, function: function, connection: conn)
        else
          _advisory_unlock_key_once(key, function: function, connection: conn) while owns_advisory_lock_key?(key, connection: conn)
        end
      end

      private

      # Executes a single pg_advisory_unlock call and updates bookkeeping.
      # Used by {.advisory_unlock_key} and {.advisory_unlock_key!} to avoid
      # mutual recursion when CTE-aware cleanup is needed.
      # @param key [String, Symbol] Key to unlock
      # @param function [String, Symbol] Postgres Advisory Lock unlock function name
      # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter]
      # @return [Boolean] whether the lock was released
      def _advisory_unlock_key_once(key, function:, connection:)
        raise ArgumentError, "Cannot unlock transactional locks" if function.include? "_xact_"
        raise ArgumentError, "No unlock function provided" if function.blank?

        query = <<~SQL.squish
          SELECT #{function}(('x'||substr(md5($1::text), 1, 16))::bit(64)::bigint) AS unlocked
        SQL
        binds = [
          ActiveRecord::Relation::QueryAttribute.new('key', key, ActiveRecord::Type::String.new),
        ]
        result = connection.exec_query(pg_or_jdbc_query(query), 'GoodJob::Lockable Advisory Unlock', binds).first['unlocked']
        record_advisory_unlock(connection, key)
        result
      end

      public

      # Tests whether the provided key has an advisory lock on it.
      # @param key [String, Symbol] Key to test lock against
      # @return [Boolean]
      def advisory_locked_key?(key)
        query = <<~SQL.squish
          SELECT 1 AS one
          FROM pg_locks
          WHERE pg_locks.locktype = 'advisory'
            AND pg_locks.objsubid = 1
            AND pg_locks.classid = ('x' || substr(md5($1::text), 1, 16))::bit(32)::int
            AND pg_locks.objid = (('x' || substr(md5($2::text), 1, 16))::bit(64) << 32)::bit(32)::int
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
      def owns_advisory_lock_key?(key, connection: nil)
        query = <<~SQL.squish
          SELECT 1 AS one
          FROM pg_locks
          WHERE pg_locks.locktype = 'advisory'
            AND pg_locks.objsubid = 1
            AND pg_locks.classid = ('x' || substr(md5($1::text), 1, 16))::bit(32)::int
            AND pg_locks.objid = (('x' || substr(md5($2::text), 1, 16))::bit(64) << 32)::bit(32)::int
            AND pg_locks.pid = pg_backend_pid()
          LIMIT 1
        SQL
        binds = [
          ActiveRecord::Relation::QueryAttribute.new('key', key, ActiveRecord::Type::String.new),
          ActiveRecord::Relation::QueryAttribute.new('key', key, ActiveRecord::Type::String.new),
        ]
        (connection || lease_connection).exec_query(pg_or_jdbc_query(query), 'GoodJob::Lockable Owns Advisory Lock?', binds).any?
      end

      def _advisory_lockable_column
        advisory_lockable_column || primary_key
      end

      def _quoted_table_name_string(name = nil)
        "'#{(name || table_name).gsub("'", "''")}'"
      end

      def supports_cte_materialization_specifiers?
        return @_supports_cte_materialization_specifiers if defined?(@_supports_cte_materialization_specifiers)

        @_supports_cte_materialization_specifiers = connection_pool.with_connection { |conn| conn.postgresql_version >= 120000 }
      end

      def record_advisory_lock(conn, key, cte: false, xact: false)
        ADVISORY_LOCK_COUNTS.record_lock(conn, key, cte: cte, xact: xact)
      end

      def record_advisory_unlock(conn, key)
        ADVISORY_LOCK_COUNTS.record_unlock(conn, key)
      end

      def prune_advisory_locks(conn)
        ADVISORY_LOCK_COUNTS.prune(conn)
      end

      # Postgres advisory unlocking function for the class
      # @param function [String, Symbol] name of advisory lock or unlock function
      # @return [Boolean]
      def advisory_unlockable_function(function = advisory_lockable_function)
        return nil if function.include? "_xact_" # Cannot unlock transactional locks

        function.to_s.sub("_lock", "_unlock").sub("_try_", "_")
      end

      # Unlocks all session-level advisory locks active in the current
      # database session/connection. Transaction-scoped locks are unaffected
      # (they release at COMMIT).
      # @return [void]
      def advisory_unlock_session(connection: nil)
        conn = connection || lease_connection
        ADVISORY_LOCK_COUNTS.clear_session_locks(conn)
        conn.exec_query("SELECT pg_advisory_unlock_all()::text AS unlocked", 'GoodJob::Lockable Unlock Session').first[:unlocked]
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
    # another database session.
    #
    # Without a block, acquires the lock and returns true/false. The caller
    # is responsible for releasing with {#advisory_unlock}.
    #
    # With a block, acquires the lock (raising {RecordAlreadyAdvisoryLockedError}
    # if it cannot), yields, and releases the lock when the block completes.
    #
    # @param key [String, Symbol] Key to Advisory Lock against
    # @param function [String, Symbol] Postgres Advisory Lock function name to use
    # @return [Boolean, Object] whether the lock was acquired (no block), or the block result.
    def advisory_lock(key: lockable_key, function: advisory_lockable_function, connection: nil, &block)
      if block
        acquired = false
        result = self.class.advisory_lock_key(key, function: function, connection: connection) do
          acquired = true
          yield
        end
        raise RecordAlreadyAdvisoryLockedError unless acquired

        result
      else
        self.class.advisory_lock_key(key, function: function, connection: connection)
      end
    end

    # Releases an advisory lock on this record if it is locked by this database
    # session. Note that advisory locks stack, so you must call
    # {#advisory_unlock} and {#advisory_lock} the same number of times.
    # @param key [String, Symbol] Key to lock against
    # @param function [String, Symbol] Postgres Advisory Lock function name to use
    # @return [Boolean] whether the lock was released.
    def advisory_unlock(key: lockable_key, function: self.class.advisory_unlockable_function(advisory_lockable_function), connection: nil)
      self.class.advisory_unlock_key(key, function: function, connection: connection || self.class.lease_connection)
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

    # @deprecated Use {#advisory_lock} with a block instead.
    def with_advisory_lock(key: lockable_key, function: advisory_lockable_function, &block)
      raise ArgumentError, "Must provide a block" unless block

      advisory_lock(key: key, function: function, &block)
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
      self.class.advisory_unlock_key!(key, function: function)
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
