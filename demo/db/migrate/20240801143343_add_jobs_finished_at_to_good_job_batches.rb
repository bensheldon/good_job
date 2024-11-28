# frozen_string_literal: true

class AddJobsFinishedAtToGoodJobBatches < ActiveRecord::Migration[7.1]
  def change
    reversible do |dir|
      dir.up do
        # Ensure this incremental update migration is idempotent
        # with monolithic install migration.
        return if connection.column_exists?(:good_job_batches, :jobs_finished_at)
      end
    end

    change_table :good_job_batches do |t|
      t.datetime :jobs_finished_at
    end
  end
end
