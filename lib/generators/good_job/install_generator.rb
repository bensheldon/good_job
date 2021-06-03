require 'rails/generators'
require 'rails/generators/active_record'
module GoodJob
  #
  # Rails generator used for setting up GoodJob in a Rails application.
  # Run it with +bin/rails g good_job:install+ in your console.
  #
  class InstallGenerator < Rails::Generators::Base
    include Rails::Generators::Migration

    class << self
      delegate :next_migration_number, to: ActiveRecord::Generators::Base
    end

    source_paths << File.join(File.dirname(__FILE__), "templates/install")

    # Generates monolithic migration file that contains all database changes.
    def create_migration_file
      migration_template 'migrations/create_good_jobs.rb.erb', 'db/migrate/create_good_jobs.rb'
    end
  end
end
