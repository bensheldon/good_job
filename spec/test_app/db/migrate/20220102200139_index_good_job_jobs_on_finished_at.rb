# frozen_string_literal: true
class IndexGoodJobJobsOnFinishedAt < ActiveRecord::Migration[6.1]
  disable_ddl_transaction!

  def change
    reversible do |dir|
      dir.up do
        # Ensure this incremental update migration is idempotent
        # with monolithic install migration.
        return if connection.index_name_exists?(:good_jobs, :index_good_jobs_on_active_job_id)
      end
    end

    add_index :good_jobs,
              [:active_job_id],
              algorithm: :concurrently,
              name: :index_good_jobs_on_active_job_id

    add_index :good_jobs,
              [:finished_at],
              algorithm: :concurrently,
              name: :index_good_jobs_jobs_on_finished_at,
              where: "retried_good_job_id IS NULL AND finished_at IS NOT NULL"
  end
end
