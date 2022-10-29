# frozen_string_literal: true
require 'rails_helper'
require 'generators/good_job/install_generator'

describe GoodJob::InstallGenerator, skip_if_java: true, type: :generator do
  around do |example|
    quiet { setup_example_app }
    example.run
    teardown_example_app
  end

  it 'creates a migration for good_jobs table' do
    quiet do
      run_in_example_app 'rails g good_job:install'
    end

    expect(Dir.glob("#{example_app_path}/db/migrate/[0-9]*_create_good_jobs.rb")).not_to be_empty
  end
end
