# frozen_string_literal: true

module GoodJob
  # Records which jobs hold (+granted+) or are waiting on (+waiting+) a claim on a
  # concurrency key. A job finishing releases its granted claims and
  # promotes the next waiting job for each released key so it runs immediately.
  #
  # Promotion means "retry now", not "reserve the next slot": the promoted job is
  # re-scheduled to run immediately and must pass the concurrency check again, so a
  # newly enqueued job can take the slot first and overtake it.
  #
  # References to jobs (+job_id+, the ActiveJob job ID) and processes (+locked_by_id+) are logical;
  # there are no database foreign keys.
  class ConcurrencyClaim < BaseRecord
    # Values of the +state+ column
    WAITING = 0
    GRANTED = 1
    # A waiting job that was promoted while it was still finishing its rejected execution;
    # the promotion is applied once its rescheduled run is saved.
    PROMOTION_PENDING = 2
    # A waiting job that has already been scheduled to retry immediately.
    PROMOTED = 3

    self.table_name = "good_job_concurrency_claims"
    self.implicit_order_column = "created_at"

    scope :granted, -> { where(state: GRANTED) }
    scope :waiting, -> { where(state: WAITING) }

    class << self
      # Grants a claim on the key if fewer than +limit+ other jobs in +scope+ are running;
      # otherwise records the job as waiting on the key, replacing any other waiting claims for the job.
      # Running jobs are counted, rather than granted claims, so that jobs performed by processes
      # that do not write claims (e.g. during a rolling deploy) are included. Running jobs that are
      # waiting on the key (rejected, but still finishing their execution) are excluded.
      # Must be called while holding the key's advisory lock, and committed before releasing it.
      # @param scope [ActiveRecord::Relation<GoodJob::Job>] the jobs counted against the limit
      # @return [Boolean] whether the claim was granted
      def claim(key:, limit:, scope:, job_id:, locked_by_id:)
        held_count = scope.running
                          .where.not(id: job_id)
                          .where.not(id: where(key: key).where.not(state: GRANTED).select(:job_id))
                          .count

        if held_count < limit
          upsert_claim(key: key, job_id: job_id, locked_by_id: locked_by_id, state: GRANTED)
          true
        else
          where(state: [WAITING, PROMOTION_PENDING, PROMOTED], job_id: job_id).where.not(key: key).delete_all
          upsert_claim(key: key, job_id: job_id, locked_by_id: nil, state: WAITING)
          false
        end
      end

      # Releases the job's granted claims and promotes a waiting job for each released key.
      # @param job_id [String] the ActiveJob job ID
      # @return [void]
      def release_job(job_id)
        keys = granted.where(job_id: job_id).pluck(:key)
        return if keys.empty?

        granted.where(job_id: job_id).delete_all
        keys.each { |key| promote_next(key) }
      end

      # Releases claims held by a process that is no longer running.
      # @return [void]
      def release_process(locked_by_id)
        keys = granted.where(locked_by_id: locked_by_id).pluck(:key)
        return if keys.empty?

        granted.where(locked_by_id: locked_by_id).delete_all
        keys.each { |key| promote_next(key) }
      end

      # Called after a job's execution has finished and been saved.
      # Releases its granted claims, removes the claims of a finished job, and runs a
      # rescheduled job immediately if it was promoted while finishing its rejected execution.
      # @param job [GoodJob::Job]
      # @return [void]
      def job_finished(job)
        release_job(job.id)

        if job.destroyed? || job.finished_at.present?
          where(job_id: job.id).delete_all
          return
        end

        promoted = transaction do
          # Lock all of the job's claims and filter by state afterwards: a promoter that has locked a
          # claim but not yet committed PROMOTION_PENDING would not match a state condition in the query.
          rows = where(job_id: job.id).lock.to_a.select { |row| row.state == PROMOTION_PENDING }
          next false if rows.empty?

          where(id: rows.map(&:id)).update_all(state: PROMOTED) # rubocop:disable Rails/SkipsModelValidations
          schedule_now(job.id)
        end
        notify(job.id) if promoted
      end

      # Deletes claims whose job no longer exists or has finished.
      # @return [Integer] number of deleted rows
      def cleanup_orphaned
        where.not(job_id: GoodJob::Job.where(finished_at: nil).select(:id)).delete_all
      end

      private

      def upsert_claim(key:, job_id:, locked_by_id:, state:)
        # Raw SQL because `upsert(update_only:)` requires Rails 7.0+
        lease_connection.exec_update(sanitize_sql_array([<<~SQL.squish, key, job_id, locked_by_id, state, Time.current]))
          INSERT INTO #{quoted_table_name} (key, job_id, locked_by_id, state, created_at)
          VALUES (?, ?, ?, ?, ?)
          ON CONFLICT (key, job_id)
          DO UPDATE SET locked_by_id = EXCLUDED.locked_by_id, state = EXCLUDED.state
        SQL
      end

      # Makes the oldest waiting job for the key runnable now. This does not reserve the
      # released slot for it; it is checked again when it runs and can be overtaken.
      def promote_next(key)
        loop do
          promoted_job_id = transaction do
            claim = waiting.where(key: key).order(:created_at).lock("FOR UPDATE SKIP LOCKED").first
            next nil unless claim

            job_exists = GoodJob::Job.exists?(id: claim.job_id, finished_at: nil)
            if !job_exists
              claim.delete
              :stale
            elsif schedule_now(claim.job_id)
              claim.update_columns(state: PROMOTED) # rubocop:disable Rails/SkipsModelValidations
              claim.job_id
            else
              # Still finishing its rejected execution; it will run itself once it is rescheduled.
              claim.update_columns(state: PROMOTION_PENDING) # rubocop:disable Rails/SkipsModelValidations
              nil
            end
          end

          next if promoted_job_id == :stale

          notify(promoted_job_id) if promoted_job_id
          break
        end
      end

      # @return [Boolean] whether a queued job was updated
      def schedule_now(job_id)
        GoodJob::Job.where(id: job_id, performed_at: nil, finished_at: nil)
                    .update_all(scheduled_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
                    .positive?
      end

      def notify(job_id)
        queue_name = GoodJob::Job.where(id: job_id).pick(:queue_name)
        GoodJob::Notifier.notify({ queue_name: queue_name }) if queue_name
      end
    end
  end
end
