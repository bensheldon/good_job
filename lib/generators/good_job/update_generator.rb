# frozen_string_literal: true
require 'rails/generators'
require 'rails/generators/active_record'

module GoodJob
  #
  # Rails generator used for updating GoodJob in a Rails application.
  # Run it with +bin/rails g good_job:update+ in your console.
  #
  class UpdateGenerator < Rails::Generators::Base
    include ActiveRecord::Generators::Migration

    TEMPLATES = File.join(File.dirname(__FILE__), "templates/update")
    source_paths << TEMPLATES

    class_option :database, type: :string, aliases: %i(--db), desc: "The database for your migration. By default, the current environment's primary database is used."

    # Generates incremental migration files unless they already exist.
    # All migrations should be idempotent e.g. +add_index+ is guarded with +if_index_exists?+
    def update_migration_files
      migration_templates = Dir.children(File.join(TEMPLATES, 'migrations')).sort
      migration_templates.each do |template_file|
        destination_file = template_file.match(/^\d*_(.*\.rb)/)[1] # 01_create_good_jobs.rb.erb => create_good_jobs.rb
        migration_template "migrations/#{template_file}", File.join(db_migrate_path, destination_file), skip: true
      end
    end
  end
end
