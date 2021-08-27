# frozen_string_literal: true
class AddActiveJobIdIndexAndConcurrencyKeyIndexToGoodJobs < ActiveRecord::Migration[5.2]
  disable_ddl_transaction!

  UPDATE_BATCH_SIZE = 1_000

  def change
    reversible do |dir|
      dir.up do
        # Ensure this incremental update migration is idempotent
        # with monolithic install migration.
        return if connection.index_name_exists?(:good_jobs, :index_good_jobs_on_active_job_id_and_created_at)
      end
    end

    add_index :good_jobs, [:active_job_id, :created_at], algorithm: :concurrently, name: :index_good_jobs_on_active_job_id_and_created_at
    add_index :good_jobs, :concurrency_key, where: "(finished_at IS NULL)", algorithm: :concurrently, name: :index_good_jobs_on_concurrency_key_when_unfinished
    add_index :good_jobs, [:cron_key, :created_at], algorithm: :concurrently, name: :index_good_jobs_on_cron_key_and_created_at

    return unless defined? GoodJob::Job

    reversible do |dir|
      dir.up do
        # Ensure that all `good_jobs` records have an active_job_id value
        start_time = Time.current
        loop do
          break if GoodJob::Job.where(active_job_id: nil, finished_at: nil).where("created_at < ?", start_time).limit(UPDATE_BATCH_SIZE).update_all("active_job_id = (serialized_params->>'job_id')::uuid").zero?
        end
      end
    end
  end
end
