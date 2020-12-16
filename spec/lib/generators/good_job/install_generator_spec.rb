require 'rails_helper'
require 'generators/good_job/install_generator'

describe GoodJob::InstallGenerator, type: :generator do
  after { remove_example_app }

  it 'creates a migration for good_jobs table' do
    expect do
      setup_example_app
    end.to output(/.*/).to_stderr_from_any_process

    expect do
      run_in_example_app 'rails g good_job:install'
    end.to output(/.*/).to_stdout_from_any_process

    expect(Dir.glob("#{example_app_path}/db/migrate/[0-9]*_create_good_jobs.rb")).not_to be_empty
  end
end
