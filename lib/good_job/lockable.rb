module GoodJob
  module Lockable
    extend ActiveSupport::Concern

    RecordAlreadyAdvisoryLockedError = Class.new(StandardError)

    included do
      scope :advisory_lock, (lambda do
        original_query = self

        cte_table = Arel::Table.new(:rows)
        composed_cte = Arel::Nodes::As.new(cte_table, original_query.select(primary_key).except(:limit).arel)

        query = cte_table.project(cte_table[:id])
                  .with(composed_cte)
                  .where(Arel.sql(sanitize_sql_for_conditions(["pg_try_advisory_lock(('x'||substr(md5(:table_name || \"#{cte_table.name}\".\"#{primary_key}\"::text), 1, 16))::bit(64)::bigint)", { table_name: table_name }])))

        limit = original_query.arel.ast.limit
        query.limit = limit.value if limit.present?

        unscoped.where(arel_table[:id].in(query)).merge(original_query.only(:order))
      end)

      scope :joins_advisory_locks, (lambda do
        join_sql = <<~SQL
          LEFT JOIN pg_locks ON pg_locks.locktype = 'advisory'
            AND pg_locks.objsubid = 1
            AND pg_locks.classid = ('x'||substr(md5(:table_name || "#{table_name}"."#{primary_key}"::text), 1, 16))::bit(32)::int
            AND pg_locks.objid = (('x'||substr(md5(:table_name || "#{table_name}"."#{primary_key}"::text), 1, 16))::bit(64) << 32)::bit(32)::int
        SQL

        joins(sanitize_sql_for_conditions([join_sql, { table_name: table_name }]))
      end)

      scope :advisory_unlocked, -> { joins_advisory_locks.where(pg_locks: { locktype: nil }) }
      scope :advisory_locked, -> { joins_advisory_locks.where.not(pg_locks: { locktype: nil }) }
      scope :owns_advisory_locked, -> { joins_advisory_locks.where('"pg_locks"."pid" = pg_backend_pid()') }

      attr_accessor :create_with_advisory_lock
      after_create -> { advisory_lock }, if: :create_with_advisory_lock
    end

    class_methods do
      def with_advisory_lock(&block)
        records = advisory_lock.to_a
        begin
          block.call(records)
        ensure
          records.each(&:advisory_unlock)
        end
      end
    end

    def advisory_lock
      query = <<~SQL
        SELECT 1 AS one
        WHERE pg_try_advisory_lock(('x'||substr(md5(:table_name || :id::text), 1, 16))::bit(64)::bigint)
      SQL
      self.class.connection.execute(sanitize_sql_for_conditions([query, { table_name: self.class.table_name, id: send(self.class.primary_key) }])).ntuples.positive?
    end

    def advisory_unlock
      query = <<~SQL
        SELECT 1 AS one
        WHERE pg_advisory_unlock(('x'||substr(md5(:table_name || :id::text), 1, 16))::bit(64)::bigint)
      SQL
      self.class.connection.execute(sanitize_sql_for_conditions([query, { table_name: self.class.table_name, id: send(self.class.primary_key) }])).ntuples.positive?
    end

    def advisory_lock!
      result = advisory_lock
      result || raise(RecordAlreadyAdvisoryLockedError)
    end

    def with_advisory_lock
      advisory_lock!
      yield
    ensure
      advisory_unlock unless $ERROR_INFO.is_a? RecordAlreadyAdvisoryLockedError
    end

    def advisory_locked?
      self.class.advisory_locked.where(id: send(self.class.primary_key)).any?
    end

    def owns_advisory_lock?
      self.class.owns_advisory_locked.where(id: send(self.class.primary_key)).any?
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
