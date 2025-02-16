# frozen_string_literal: true

class AddIndexGoodJobsConcurrencyKeyCreatedAt <ActiveRecord::Migration[8.0]
  def change
    add_index :good_jobs, [:concurrency_key, :created_at]
  end
end
