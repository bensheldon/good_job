class AddCoalesceIndex < ActiveRecord::Migration[6.1]
  def change
    add_index :good_jobs, "COALESCE(scheduled_at, created_at)", where: "(finished_at IS NULL)"
  end
end
