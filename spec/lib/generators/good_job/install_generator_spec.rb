require 'rails_helper'
require 'generators/good_job/install_generator'

describe GoodJob::InstallGenerator, type: :generator do
  after { remove_example_app }

  it 'creates a migration for good_jobs table' do
    setup_example_app

    run_in_example_app 'rails g good_job:install'

    expect(Dir.glob("#{example_app_path}/db/migrate/[0-9]*_create_good_jobs.rb")).not_to be_empty
  end
end
