class AddIndexGoodJobsJobClass < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :good_jobs, :job_class, algorithm: :concurrently
  end
end
