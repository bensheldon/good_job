# frozen_string_literal: true
class AddRetriedGoodJobIdToGoodJobs < ActiveRecord::Migration[5.2]
  def change
    reversible do |dir|
      dir.up do
        # Ensure this incremental update migration is idempotent
        # with monolithic install migration.
        return if connection.column_exists?(:good_jobs, :retried_good_job_id)
      end
    end

    add_column :good_jobs, :retried_good_job_id, :uuid
  end
end
