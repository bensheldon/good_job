# frozen_string_literal: true

class AddIndexGoodJobExecutionsOnCreatedAt < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :good_job_executions, :created_at,
              name: :index_good_job_executions_on_created_at,
              algorithm: :concurrently,
              if_not_exists: true
  end
end
