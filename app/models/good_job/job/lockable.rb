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
            yield(record).tap { record&.run_callbacks(:perform_unlocked) }
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
          with_row_lock_claim(locked_by_id: locked_by_id, locked_at: locked_at, lock_type: lock_type, &block)
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
          with_row_lock_claim(locked_by_id: locked_by_id, locked_at: locked_at, lock_type: lock_type, advisory: true, &block)
        end

        private

        def with_row_lock_claim(locked_by_id:, locked_at:, lock_type:, advisory: false, &block)
          raise ArgumentError, "Must provide a block" unless block

          connection = lease_connection if advisory # retain the session holding the advisory lock
          candidate_sql = select(:id).lock("FOR NO KEY UPDATE SKIP LOCKED").to_sql
          materialized = supports_cte_materialization_specifiers? ? "MATERIALIZED " : ""
          candidate_filter = if advisory
                               advisory_key = advisory_lock_bigint_sql("#{_quoted_table_name_string} || '-' || id::text")
                               "WHERE pg_try_advisory_lock(#{advisory_key})"
                             end

          sql = <<~SQL.squish
            WITH candidate AS #{materialized}(#{candidate_sql})
            UPDATE #{quoted_table_name}
            SET locked_by_id = ?,
                locked_at = ?,
                lock_type = ?
            FROM (SELECT id FROM candidate #{candidate_filter}) AS locked
            WHERE #{quoted_table_name}.id = locked.id
            RETURNING #{quoted_table_name}.*
          SQL

          record = unscoped.find_by_sql([sql, locked_by_id, locked_at, lock_types[lock_type.to_s]]).first
          record_advisory_lock(connection, record.lockable_column_key, cte: true) if advisory && record

          completed = false
          begin
            result = unscoped { yield(record) }
            completed = true
            result
          ensure
            begin
              record.advisory_unlock(connection: connection) if advisory && record
            ensure
              # A failed completion may have cleared the attributes in memory only.
              if record && (!completed || (!record.destroyed? && record.locked_by_id_in_database.present?))
                released = release_lock_claim(record, locked_by_id: locked_by_id, locked_at: locked_at)
                completed &&= released
              end
            end
            record&.run_callbacks(:perform_unlocked) if completed
          end
        end

        def release_lock_claim(record, locked_by_id:, locked_at:)
          transaction do
            # Match the original claim, including its time, so a newer execution is untouched.
            released = unscoped.where(id: record.id, locked_by_id: locked_by_id, locked_at: locked_at)
                               .update_all(locked_by_id: nil, locked_at: nil, lock_type: nil) # rubocop:disable Rails/SkipsModelValidations
            if released.positive?
              GoodJob::ConcurrencyClaim.release_job(record.id) if GoodJob::ConcurrencyClaim.table_exists?
              record.reload
            end
            released.positive?
          end
        rescue StandardError => e
          connection_errors = %w[ActiveRecord::ConnectionNotEstablished ActiveRecord::ConnectionFailed PG::ConnectionBad PG::UnableToSend].filter_map(&:safe_constantize)
          cause = e.is_a?(ActiveRecord::StatementInvalid) ? e.cause : nil # older Rails wraps PG connection errors
          raise unless connection_errors.any? { |klass| e.is_a?(klass) || cause.is_a?(klass) }
          return false if Thread.current.status == "aborting"

          # Keep the worker registered until its claim can be released. Otherwise a
          # live process can keep the abandoned job locked indefinitely.
          sleep 5
          retry
        end
      end
    end
  end
end
