# frozen_string_literal: true

class EnableUuidOssp < ActiveRecord::Migration[7.0]
  def change
    enable_extension "uuid-ossp"
  end
end
