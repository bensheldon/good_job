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
