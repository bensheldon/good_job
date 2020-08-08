class AddLifecycleTimestampsToGoodJobs < ActiveRecord::Migration[6.0]
  def change
    add_column :good_jobs, :performed_at, :timestamp
    add_column :good_jobs, :finished_at, :timestamp
    add_column :good_jobs, :error, :text

    remove_index :good_jobs, :scheduled_at
    remove_index :good_jobs, [:queue_name, :scheduled_at]

    add_index :good_jobs, :scheduled_at, where: "(finished_at IS NULL)"
    add_index :good_jobs, [:queue_name, :scheduled_at], where: "(finished_at IS NULL)"
  end
end
