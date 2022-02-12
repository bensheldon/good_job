# frozen_string_literal: true
require 'rails_helper'
require 'generators/good_job/update_generator'

describe GoodJob::UpdateGenerator, type: :generator, skip_if_java: true do
  context 'when running the generator alone' do
    around do |example|
      within_example_app do
        example.run
      end
    end

    it 'creates migrations for good_jobs table' do
      quiet do
        run_in_example_app 'rails g good_job:update'
      end

      expect(Dir.glob("#{example_app_path}/db/migrate/[0-9]*_create_good_jobs.rb")).not_to be_empty
      # TODO: replace this when migrations are re-added
      # expect(Dir.glob("#{example_app_path}/db/migrate/[0-9]*_add_active_job_id_index_and_concurrency_key_index_to_good_jobs.rb")).not_to be_empty

      quiet do
        run_in_example_app 'rails db:migrate'
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

  def normalize_schema(text)
    text.sub(/\.define\(version: ([\d_]*)\)/, '.define(version: SCHEMA_VERSION)')
  end
end
