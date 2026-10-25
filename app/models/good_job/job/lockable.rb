# frozen_string_literal: true

module GoodJob
  class Job < BaseRecord
    # Adds row-level locking capabilities (SKIP LOCKED) to GoodJob::Job.
    # These methods provide strategy-agnostic job claiming via CTE UPDATE statements.
    # All methods require a block.
    module Lockable
      extend ActiveSupport::Concern

      class_methods do
        # Claims a job by acquiring a session-level advisory lock via the CTE
        # query, and records the lock acquisition for phantom re-entrancy cleanup.
        # Yields the claimed record (or nil if none found), then releases the
        # advisory lock when the block completes.
        #
        # @param select_limit [Integer, nil] Number of candidates to attempt locking
        # @yield [GoodJob::Job, nil] The claimed record, or nil if none found
        # @return [Object] The return value of the block
        def with_advisory_lock_claim(select_limit: nil, &block)
          raise ArgumentError, "Must provide a block" unless block

          advisory_lock(select_limit: select_limit) do |records|
            record = records.first
            begin
              yield(record)
            ensure
              record&.run_callbacks(:perform_unlocked)
            end
          end
        end

        # Atomically claims a job using SELECT FOR NO KEY UPDATE SKIP LOCKED in a CTE UPDATE.
        # Yields the claimed record (or nil if none found). No advisory locks
        # are acquired so no unlock is needed.
        #
        # @param locked_by_id [String] The process UUID claiming the job
        # @param locked_at [Time] When the job was claimed
        # @param lock_type [String, Symbol] Lock type identifier
        # @yield [GoodJob::Job, nil] The claimed record, or nil if none found
        # @return [Object] The return value of the block
        def with_skip_locked_claim(locked_by_id:, locked_at:, lock_type:, &block)
          raise ArgumentError, "Must provide a block" unless block

          candidate_sql = select(:id).lock("FOR NO KEY UPDATE SKIP LOCKED").to_sql
          materialized = supports_cte_materialization_specifiers? ? "MATERIALIZED " : ""

          sql = <<~SQL.squish
            WITH candidate AS #{materialized}(#{candidate_sql})
            UPDATE #{quoted_table_name}
            SET locked_by_id = ?,
                locked_at = ?,
                lock_type = ?
            FROM candidate
            WHERE #{quoted_table_name}.id = candidate.id
            RETURNING #{quoted_table_name}.*
          SQL

          record = unscoped.find_by_sql([sql, locked_by_id, locked_at, lock_types[lock_type.to_s]]).first

          completed = false
          begin
            result = unscoped { yield(record) }
            completed = true
            result
          ensure
            release_lock_claim(record, locked_by_id: locked_by_id, locked_at: locked_at, completed: completed)
            record&.run_callbacks(:perform_unlocked)
          end
        end

        # Atomically claims a job using SELECT FOR NO KEY UPDATE SKIP LOCKED with an
        # additional session-level advisory lock acquired within the same statement.
        # Yields the claimed record (or nil if none found), then releases the
        # advisory lock when the block completes.
        #
        # @param locked_by_id [String] The process UUID claiming the job
        # @param locked_at [Time] When the job was claimed
        # @param lock_type [String, Symbol] Lock type identifier
        # @yield [GoodJob::Job, nil] The claimed record, or nil if none found
        # @return [Object] The return value of the block
        def with_hybrid_lock_claim(locked_by_id:, locked_at:, lock_type:, &block)
          raise ArgumentError, "Must provide a block" unless block

          lease_connection # sticky connection; advisory lock must outlive this statement

          candidate_sql = select(:id).lock("FOR NO KEY UPDATE SKIP LOCKED").to_sql
          advisory_lock_expr = "('x' || substr(md5(#{_quoted_table_name_string} || '-' || id::text), 1, 16))::bit(64)::bigint"
          materialized = supports_cte_materialization_specifiers? ? "MATERIALIZED " : ""

          sql = <<~SQL.squish
            WITH candidate AS #{materialized}(#{candidate_sql})
            UPDATE #{quoted_table_name}
            SET locked_by_id = ?,
                locked_at = ?,
                lock_type = ?
            FROM (
              SELECT id FROM candidate
              WHERE pg_try_advisory_lock(#{advisory_lock_expr})
            ) AS locked
            WHERE #{quoted_table_name}.id = locked.id
            RETURNING #{quoted_table_name}.*
          SQL

          record = unscoped.find_by_sql([sql, locked_by_id, locked_at, lock_types[lock_type.to_s]]).first
          record_advisory_lock(lease_connection, record.lockable_column_key, cte: true) if record

          completed = false
          begin
            result = unscoped { yield(record) }
            completed = true
            result
          ensure
            if record
              begin
                record.advisory_unlock
              ensure
                release_lock_claim(record, locked_by_id: locked_by_id, locked_at: locked_at, completed: completed)
              end
            end
            record&.run_callbacks(:perform_unlocked)
          end
        end

        private

        def release_lock_claim(record, locked_by_id:, locked_at:, completed:)
          return unless record
          return if completed && (record.destroyed? || record.locked_by_id_in_database.blank?)

          # Keep the execution registered until cleanup succeeds. Returning while
          # the database is unavailable would orphan the claim under a live process.
          retry_on_connection_error(attempts: Float::INFINITY) do
            transaction do
              # Completion may have cleared these attributes in memory without
              # committing them. Only release this claim, without saving dirty fields.
              released = unscoped.where(id: record.id, locked_by_id: locked_by_id, locked_at: locked_at)
                                 .update_all(locked_by_id: nil, locked_at: nil, lock_type: nil) # rubocop:disable Rails/SkipsModelValidations
              GoodJob::ConcurrencyClaim.release_job(record.id) if released.positive? && GoodJob::ConcurrencyClaim.table_exists?
              # Unlocked callbacks must see the persisted result, not an
              # uncommitted finished_at/error that could discard a batch.
              record.reload if released.positive?
            end
          end
        end
      end
    end
  end
end
