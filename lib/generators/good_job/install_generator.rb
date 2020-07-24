require 'rails/generators'
require 'rails/generators/active_record'

module GoodJob
  class InstallGenerator < Rails::Generators::Base
    include Rails::Generators::Migration

    class << self
      delegate :next_migration_number, to: ActiveRecord::Generators::Base
    end

    source_paths << File.join(File.dirname(__FILE__), "templates")

    def create_migration_file
      migration_template 'migration.rb', 'db/migrate/create_good_jobs.rb',  migration_version: migration_version
    end

    private

    def migration_version
      "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
    end
  end
end
