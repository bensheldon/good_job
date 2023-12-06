# frozen_string_literal: true
class AddCronKeyCronAtIndexToGoodJobs < ActiveRecord::Migration[5.2]
  disable_ddl_transaction!

  def change
    reversible do |dir|
      dir.up do
        # Ensure this incremental update migration is idempotent
        # with monolithic install migration.
        return if connection.index_name_exists?(:good_jobs, :index_good_jobs_on_cron_key_and_cron_at)
      end
    end

    add_index :good_jobs,
              [:cron_key, :cron_at],
              algorithm: :concurrently,
              name: :index_good_jobs_on_cron_key_and_cron_at,
              unique: true
  end
end
