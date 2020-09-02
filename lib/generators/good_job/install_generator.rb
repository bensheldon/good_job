require 'rails/generators'
require 'rails/generators/active_record'

module GoodJob
  #
  # Implements the Rails generator used for setting up GoodJob in a Rails
  # application. Run it with +bin/rails g good_job:install+ in your console.
  #
  # This generator is primarily dedicated to stubbing out a migration that adds
  # a table to hold GoodJob's queued jobs in your database.
  #
  class InstallGenerator < Rails::Generators::Base
    include Rails::Generators::Migration

    class << self
      delegate :next_migration_number, to: ActiveRecord::Generators::Base
    end

    source_paths << File.join(File.dirname(__FILE__), "templates")

    # Generates the actual migration file and places it on disk.
    def create_migration_file
      migration_template 'migration.rb.erb', 'db/migrate/create_good_jobs.rb', migration_version: migration_version
    end

    private

    def migration_version
      "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
    end
  end
end
