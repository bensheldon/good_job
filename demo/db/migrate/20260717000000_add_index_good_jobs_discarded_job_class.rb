# frozen_string_literal: true

class AddIndexGoodJobsDiscardedJobClass < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :good_jobs, [:job_class, :finished_at],
      name: :index_good_jobs_on_discarded_job_class,
      where: "finished_at IS NOT NULL AND error IS NOT NULL",
      algorithm: :concurrently,
      if_not_exists: true
  end
end
