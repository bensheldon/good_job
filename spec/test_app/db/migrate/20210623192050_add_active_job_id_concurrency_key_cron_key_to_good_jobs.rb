class AddActiveJobIdConcurrencyKeyCronKeyToGoodJobs < ActiveRecord::Migration[5.2]
  def change
    reversible do |dir|
      dir.up do
        # Ensure this incremental update migration is idempotent
        # with monolithic install migration.
        return if connection.column_exists?(:good_jobs, :active_job_id)
      end
    end

    add_column :good_jobs, :active_job_id, :uuid
    add_column :good_jobs, :concurrency_key, :text
    add_column :good_jobs, :cron_key, :text
  end
end
