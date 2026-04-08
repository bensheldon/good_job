# frozen_string_literal: true

module GoodJob
  # Adds row-level locking capabilities (SKIP LOCKED) to ActiveRecord models.
  # These methods provide strategy-agnostic job claiming via CTE UPDATE statements.
  module Lockable
    extend ActiveSupport::Concern

    class_methods do
      # Claims a job by acquiring a session-level advisory lock.
      # Returns the claimed record or nil if no eligible record was found.
      # The caller is responsible for releasing the advisory lock after use.
      # @param select_limit [Integer, nil] Number of candidates to attempt locking
      # @return [ActiveRecord::Base, nil]
      def with_advisory_lock_claim(select_limit: nil)
        advisory_lock(select_limit: select_limit).first
      end

      # Atomically claims a job using SELECT FOR NO KEY UPDATE SKIP LOCKED in a CTE UPDATE.
      # Returns the claimed record or nil if no eligible record was found.
      # @param locked_by_id [String] The process UUID claiming the job
      # @param locked_at [Time] When the job was claimed
      # @param lock_type [String, Symbol] Lock type identifier
      # @return [ActiveRecord::Base, nil]
      def with_skip_locked_claim(locked_by_id:, locked_at:, lock_type:)
        candidate_sql = select(:id).lock("FOR NO KEY UPDATE SKIP LOCKED").to_sql
        quoted_table = adapter_class.quote_table_name(table_name)
        materialized = supports_cte_materialization_specifiers? ? "MATERIALIZED " : ""

        sql = <<~SQL.squish
          WITH candidate AS #{materialized}(#{candidate_sql})
          UPDATE #{quoted_table}
          SET locked_by_id = ?,
              locked_at = ?,
              lock_type = ?
          FROM candidate
          WHERE #{quoted_table}.id = candidate.id
          RETURNING #{quoted_table}.*
        SQL

        unscoped.find_by_sql([sql, locked_by_id, locked_at, lock_types[lock_type.to_s]]).first
      end

      # Atomically claims a job using SELECT FOR NO KEY UPDATE SKIP LOCKED with an
      # additional session-level advisory lock acquired within the same statement.
      # Returns the claimed record or nil if no eligible record was found.
      # @param locked_by_id [String] The process UUID claiming the job
      # @param locked_at [Time] When the job was claimed
      # @param lock_type [String, Symbol] Lock type identifier
      # @return [ActiveRecord::Base, nil]
      def with_hybrid_lock_claim(locked_by_id:, locked_at:, lock_type:)
        candidate_sql = select(:id).lock("FOR NO KEY UPDATE SKIP LOCKED").to_sql
        quoted_table = adapter_class.quote_table_name(table_name)
        advisory_lock_expr = "('x' || substr(md5(#{_quoted_table_name_string} || '-' || id::text), 1, 16))::bit(64)::bigint"
        materialized = supports_cte_materialization_specifiers? ? "MATERIALIZED " : ""

        sql = <<~SQL.squish
          WITH candidate AS #{materialized}(#{candidate_sql})
          UPDATE #{quoted_table}
          SET locked_by_id = ?,
              locked_at = ?,
              lock_type = ?
          FROM (
            SELECT id FROM candidate
            WHERE pg_try_advisory_lock(#{advisory_lock_expr})
          ) AS locked
          WHERE #{quoted_table}.id = locked.id
          RETURNING #{quoted_table}.*
        SQL

        unscoped.find_by_sql([sql, locked_by_id, locked_at, lock_types[lock_type.to_s]]).first
      end
    end
  end
end
