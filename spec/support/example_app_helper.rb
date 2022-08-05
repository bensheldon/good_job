# frozen_string_literal: true
require 'fileutils'

module ExampleAppHelper
  def setup_example_app
    FileUtils.rm_rf(example_app_path)

    # Rails will not install within a directory containing `bin/rails`
    File.rename(Rails.root.join("../../bin/rails"), Rails.root.join("../../bin/_rails")) if File.exist?(Rails.root.join("../../bin/rails"))

    root_path = example_app_path.join('..')
    FileUtils.cd(root_path) do
      system("rails new #{app_name} -d postgresql --no-assets --skip-action-text --skip-action-mailer --skip-action-mailbox --skip-action-cable --skip-git --skip-sprockets --skip-listen --skip-javascript --skip-turbolinks --skip-system-test --skip-test-unit --skip-bootsnap --skip-spring --skip-active-storage")
    end

    FileUtils.rm_rf("#{example_app_path}/config/initializers/assets.rb")
    FileUtils.cp(::Rails.root.join('config', 'database.yml'), "#{example_app_path}/config/database.yml")

    File.open("#{example_app_path}/Gemfile", 'a') do |f|
      f.puts 'gem "good_job", path: "#{File.dirname(__FILE__)}/../../../"' # rubocop:disable Lint/InterpolationCheck
    end
  end

  def teardown_example_app
    File.rename(Rails.root.join("../../bin/_rails"), Rails.root.join("../../bin/rails"))
    FileUtils.rm_rf(example_app_path)
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

  def within_example_app
    # Will be running database migrations from the newly created Example App
    # but doing so in the existing database. This resets the database so that
    # newly created migrations can be run, then resets it back.
    #
    # Ideally this would happen in a different database, but that seemed like
    # a lot of work to do in Github Actions.
    tables = [:good_jobs, :good_job_processes, :good_job_settings]
    quiet do
      tables.each do |table_name|
        ActiveRecord::Migration.drop_table(table_name) if ActiveRecord::Base.connection.table_exists?(table_name)
      end
      ActiveRecord::Base.connection.execute("TRUNCATE schema_migrations")

      setup_example_app
      run_in_test_app("bin/rails db:environment:set RAILS_ENV=test")
    end

    yield
  ensure
    quiet do
      teardown_example_app

      tables.each do |table_name|
        ActiveRecord::Migration.drop_table(table_name) if ActiveRecord::Base.connection.table_exists?(table_name)
      end
      ActiveRecord::Base.connection.execute("TRUNCATE schema_migrations")

      run_in_test_app("bin/rails db:schema:load db:environment:set RAILS_ENV=test")
    end
  end

  def example_app_path
    Rails.root.join('../tmp', app_name)
  end

  def app_name
    'example_app'
  end
end

RSpec.configure { |c| c.include ExampleAppHelper, type: :generator }
