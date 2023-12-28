# frozen_string_literal: true

require 'rails_helper'
require 'generators/good_job/install_generator'

describe GoodJob::InstallGenerator, :skip_if_java, type: :generator do
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

  it 'creates empty partials for good_job views' do
    quiet do
      run_in_example_app 'rails g good_job:install'
    end

    custom_partials = Dir.glob("#{example_app_path}/app/views/good_job/jobs/_custom_*.html.erb")
    expect(custom_partials).not_to be_empty
    expect(custom_partials.map { |p| File.read(p) }).to all(match(/internal implementation detail/))
  end
end
