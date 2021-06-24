require 'fileutils'

module ExampleAppHelper
  def setup_example_app
    FileUtils.rm_rf(example_app_path)

    root_path = example_app_path.join('..')
    FileUtils.cd(root_path) do
      system("rails new #{app_name} -d postgresql --no-assets --skip-action-text --skip-action-mailer --skip-action-mailbox --skip-action-cable --skip-git --skip-sprockets --skip-listen --skip-javascript --skip-turbolinks --skip-system-test --skip-test-unit --skip-bootsnap --skip-spring --skip-active-storage")
    end

    File.open("#{example_app_path}/Gemfile", 'a') do |f|
      f.puts "gem 'good_job'"
    end
  end

  def run_in_example_app(*args)
    FileUtils.cd(example_app_path) do
      system(*args) || raise("Command #{args} failed")
    end
  end

  def run_in_test_app(*args)
    FileUtils.cd(Rails.root) do
      system(*args) || raise("Command #{args} failed")
    end
  end

  def remove_example_app
    FileUtils.rm_rf(example_app_path)
  end

  def within_example_app
    # Will be running database migrations from the newly created Example App
    # but doing so in the existing database. This resets the database so that
    # newly created migrations can be run, then resets it back.
    #
    # Ideally this would happen in a different database, but that seemed like
    # a lot of work to do in Github Actions.
    quiet do
      ActiveRecord::Migration.drop_table(:good_jobs) if ActiveRecord::Base.connection.table_exists?(:good_jobs)
      ActiveRecord::Base.connection.execute("TRUNCATE schema_migrations")

      setup_example_app
      run_in_test_app("bin/rails db:environment:set RAILS_ENV=test")
    end

    yield

    quiet do
      remove_example_app

      ActiveRecord::Migration.drop_table(:good_jobs) if ActiveRecord::Base.connection.table_exists?(:good_jobs)
      ActiveRecord::Base.connection.execute("TRUNCATE schema_migrations")

      run_in_test_app("bin/rails db:schema:load db:environment:set RAILS_ENV=test")
    end
  end

  def example_app_path
    Rails.root.join('../tmp', app_name)
  end

  def app_name
    'test_app'
  end
end

RSpec.configure { |c| c.include ExampleAppHelper, type: :generator }
