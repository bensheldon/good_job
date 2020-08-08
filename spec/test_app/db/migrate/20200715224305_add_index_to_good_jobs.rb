class AddIndexToGoodJobs < ActiveRecord::Migration[6.0]
  def change
    add_index :good_jobs, :scheduled_at
    add_index :good_jobs, [:queue_name, :scheduled_at]
  end
end
