class CreateGoodJobs < ActiveRecord::Migration<%= migration_version %>
  def change
    enable_extension 'pgcrypto'

    create_table :good_jobs, id: :uuid do |t|
      t.text :queue_name
      t.integer :priority
      t.jsonb :serialized_params
      t.timestamp :scheduled_at
      t.timestamp :performed_at
      t.timestamp :finished_at
      t.text :error

      t.timestamps
    end

    add_index :good_jobs, :scheduled_at, where: "(finished_at IS NULL)"
    add_index :good_jobs, [:queue_name, :scheduled_at], where: "(finished_at IS NULL)"
  end
end
