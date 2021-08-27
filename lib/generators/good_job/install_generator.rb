# frozen_string_literal: true
require 'rails/generators'
require 'rails/generators/active_record'

module GoodJob
  #
  # Rails generator used for setting up GoodJob in a Rails application.
  # Run it with +bin/rails g good_job:install+ in your console.
  #
  class InstallGenerator < Rails::Generators::Base
    include ActiveRecord::Generators::Migration

    TEMPLATES = File.join(File.dirname(__FILE__), "templates/install")
    source_paths << TEMPLATES

    class_option :database, type: :string, aliases: %i(--db), desc: "The database for your migration. By default, the current environment's primary database is used."

    # Generates monolithic migration file that contains all database changes.
    def create_migration_file
      migration_template 'migrations/create_good_jobs.rb.erb', File.join(db_migrate_path, "create_good_jobs.rb")
    end
  end
end
