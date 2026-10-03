# frozen_string_literal: true

class RemoveRedundantGoodJobsIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    remove_index(
      :good_jobs,
      name: :index_good_jobs_jobs_on_priority_created_at_when_unfinished,
      algorithm: :concurrently,
      if_exists: true
    )
    remove_index(
      :good_jobs,
      name: :index_good_jobs_on_priority_scheduled_at_unfinished_unlocked,
      algorithm: :concurrently,
      if_exists: true
    )
    remove_index(
      :good_jobs,
      name: :index_good_jobs_on_queue_name_and_scheduled_at,
      algorithm: :concurrently,
      if_exists: true
    )
  end

  def down
    add_index(
      :good_jobs,
      [:priority, :created_at],
      name: :index_good_jobs_jobs_on_priority_created_at_when_unfinished,
      order: { priority: "DESC NULLS LAST", created_at: :asc },
      where: "finished_at IS NULL",
      algorithm: :concurrently,
      if_not_exists: true
    )
    add_index(
      :good_jobs,
      [:priority, :scheduled_at],
      name: :index_good_jobs_on_priority_scheduled_at_unfinished_unlocked,
      order: { priority: "ASC NULLS LAST", scheduled_at: :asc },
      where: "finished_at IS NULL AND locked_by_id IS NULL",
      algorithm: :concurrently,
      if_not_exists: true
    )
    add_index(
      :good_jobs,
      [:queue_name, :scheduled_at],
      name: :index_good_jobs_on_queue_name_and_scheduled_at,
      where: "finished_at IS NULL",
      algorithm: :concurrently,
      if_not_exists: true
    )
  end
end
