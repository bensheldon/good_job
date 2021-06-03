require 'rails/generators'
require 'rails/generators/active_record'

module GoodJob
  #
  # Rails generator used for updating GoodJob in a Rails application.
  # Run it with +bin/rails g good_job:update+ in your console.
  #
  class UpdateGenerator < Rails::Generators::Base
    include Rails::Generators::Migration

    class << self
      delegate :next_migration_number, to: ActiveRecord::Generators::Base
    end

    TEMPLATES = File.join(File.dirname(__FILE__), "templates/update")
    source_paths << TEMPLATES

    # Generates incremental migration files unless they already exist.
    # All migrations should be idempotent e.g. +add_index+ is guarded with +if_index_exists?+
    def update_migration_files
      migration_templates = Dir.children(File.join(TEMPLATES, 'migrations')).sort
      migration_templates.each do |template_file|
        destination_file = template_file.match(/^\d*_(.*\.rb)/)[1] # 01_create_good_jobs.rb.erb => create_good_jobs.rb
        migration_template "migrations/#{template_file}", "db/migrate/#{destination_file}", skip: true
      end
    end
  end
end
