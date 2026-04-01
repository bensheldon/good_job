# frozen_string_literal: true

class AddIndexGoodJobsQueuePriorityScheduledAt < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    reversible do |dir|
      dir.up do
        # Ensure this incremental update migration is idempotent
        # with monolithic install migration.
        return if connection.index_exists? :good_jobs, [:queue_name, :priority, :scheduled_at, :created_at, :id], name: "index_good_jobs_on_queue_name_priority_scheduled_at_unfinished"
      end
    end

    add_index :good_jobs, [:queue_name, :priority, :scheduled_at, :created_at, :id],
                                                      where: "finished_at IS NULL", name: "index_good_jobs_on_queue_name_priority_scheduled_at_unfinished",
                                                      algorithm: :concurrently
  end
end
