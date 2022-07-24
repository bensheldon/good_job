# frozen_string_literal: true
class AddCronAtToGoodJobs < ActiveRecord::Migration[5.2]
  def change
    reversible do |dir|
      dir.up do
        # Ensure this incremental update migration is idempotent
        # with monolithic install migration.
        return if connection.column_exists?(:good_jobs, :cron_at)
      end
    end

    add_column :good_jobs, :cron_at, :datetime
  end
end
