# frozen_string_literal: true
class CreateGoodJobSettings < ActiveRecord::Migration[6.1]
  def change
    create_table :good_job_settings, id: :uuid do |t|
      t.timestamps
      t.text :key
      t.jsonb :value
      t.index :key, unique: true
    end
  end
end
