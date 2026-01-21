# frozen_string_literal: true

require 'rails_helper'
require 'generators/good_job/update_generator'

describe GoodJob::UpdateGenerator, :skip_if_java, type: :generator do
  context 'when running the generator alone' do
    # Migrations are caught up and removed every major release of GoodJob
    let(:migration_templates) { Rails.application.root.join("../lib/generators/good_job/templates/update/migrations").glob("*.erb") }

    around do |example|
      within_example_app do
        example.run
      end
    end

    it 'creates migrations for good_jobs table' do
      quiet do
        run_in_example_app 'rails g good_job:update'
      end

      if migration_templates.any?
        # Check that templates are copied over
        first_migration_filematch = File.basename(migration_templates.first).match(/^\d+(_.*)\.erb$/)[1]
        expect(Dir.glob("#{example_app_path}/db/migrate/[0-9]*#{first_migration_filematch}")).not_to be_empty
      end

      quiet do
        run_in_example_app 'rails db:migrate'
      end

      # Check that `GoodJob.migrated?` is updated
      expect(GoodJob.migrated?).to be true

      if migration_templates.any?
        # Check that migrations cleanly rollback and forward
        quiet do
          run_in_example_app 'rails db:rollback'
          expect(GoodJob.migrated?).to be false
          run_in_example_app 'rails db:migrate'
        end
        expect(GoodJob.migrated?).to be true
      end
    end
  end

  context 'when running the generator with --database option' do
    around do |example|
      within_example_app do
        # Setup custom database configuration
        database_yml_path = example_app_path.join('config/database.yml')
        database_yml_content = YAML.safe_load(ERB.new(File.read(database_yml_path)).result, aliases: true)

        # In Rails 6+, we can have multiple databases per environment
        # Reuse the same database name but under a custom key
        database_yml_content['test'] = {
          'primary' => database_yml_content['test'],
          'custom' => database_yml_content['test'].merge({
                                                           'migrations_paths' => 'db/migrate_custom',
                                                         }),
        }
        File.write(database_yml_path, YAML.dump(database_yml_content))

        example.run
      end
    end

    it 'creates migrations in the custom database path and they are runnable' do
      run_in_example_app 'rails g good_job:update --database custom'

      expect(example_app_path.join('db/migrate_custom')).to exist
      migration_file = Dir.glob(example_app_path.join('db/migrate_custom/*.rb')).first
      expect(migration_file).not_to be_nil

      run_in_example_app 'rails db:migrate'

      output = run_in_example_app "rails db:migrate:status"
      expect(output).not_to include('  down  ')
    end
  end

  it 'produces an idempotent schema.rb when run with install generator' do
    install_schema = ""
    update_after_install_schema = ""
    only_update_schema = ""

    within_example_app do
      quiet { run_in_example_app 'rails g good_job:install; rails db:migrate' }
      install_schema = File.read example_app_path.join('db', 'schema.rb')

      quiet { run_in_example_app 'rails g good_job:update; rails db:migrate' }
      update_after_install_schema = File.read example_app_path.join('db', 'schema.rb')
    end

    expect(normalize_schema(update_after_install_schema)).to eq normalize_schema(install_schema)

    within_example_app do
      quiet { run_in_example_app 'rails g good_job:update; rails db:migrate' }
      only_update_schema = File.read example_app_path.join('db', 'schema.rb')
    end

    expect(normalize_schema(only_update_schema)).to eq normalize_schema(install_schema)
  end

  it 'has files with unique number prefixes' do
    update_path = "lib/generators/good_job/templates/update/migrations"
    expect(File).to exist(update_path)

    migrations = Dir.glob("#{update_path}/*")
    prefixes = migrations.map { |path| File.basename(path).split("_", 2).first }

    expect(prefixes.map(&:to_i).sort).to eq(1.upto(prefixes.size).to_a)
  end

  def normalize_schema(text)
    text.sub(/\.define\(version: ([\d_]*)\)/, '.define(version: SCHEMA_VERSION)')
  end
end
