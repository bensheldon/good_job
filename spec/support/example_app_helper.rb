require 'fileutils'

module ExampleAppHelper
  def setup_example_app
    root_path = example_app_path.join('..')

    FileUtils.cd(root_path) do
      `rails new #{app_name} -d postgresql --no-assets --skip-action-text --skip-action-mailer --skip-action-mailbox --skip-action-cable --skip-sprockets --skip-listen --skip-javascript --skip-turbolinks --skip-system-test --skip-test-unit --skip-bootsnap --skip-spring --skip-active-storage`
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

  def remove_example_app
    FileUtils.rm_rf(example_app_path)
  end

  def example_app_path
    Rails.root.join('..', app_name)
  end

  def app_name
    'example_app'
  end
end

RSpec.configure { |c| c.include ExampleAppHelper, type: :generator }
