# frozen_string_literal: true

# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'

if RUBY_PLATFORM.include?('java')
  # Workaround for issue in I18n/JRuby combo.
  # See https://github.com/jruby/jruby/issues/6547 and
  # https://github.com/ruby-i18n/i18n/issues/555
  require "i18n/backend"
  require "i18n/backend/simple"
end

require "timecop"

require "warning"
# https://github.com/mikel/mail/pull/1557
Warning.ignore(%r{/lib/mail/parsers/})
# https://github.com/SeleniumHQ/selenium/pull/14770
Warning.ignore(%r{/lib/selenium/.*URI::RFC3986_PARSER.escape is obsolete})
# https://github.com/teamcapybara/capybara/pull/2781
Warning.ignore(%r{/lib/capybara/.*URI::RFC3986_PARSER.make_regexp is obsolete})
# https://github.com/rails/rails/pull/54053
Warning.ignore(%r{the block passed to 'ActiveModel::Type::Value#serializable\?'})
Warning.ignore(%r{the block passed to 'ActiveModel::Attribute#value'})

require File.expand_path('../demo/config/environment', __dir__)

# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'
# Add additional requires below this line. Rails is not loaded until this point!

# Requires supporting ruby files with custom matchers and macros, etc, in
# spec/support/ and its subdirectories. Files matching `spec/**/*_spec.rb` are
# run as spec files by default. This means that files in spec/support that end
# in _spec.rb will both be required and run as specs, causing the specs to be
# run twice. It is recommended that you do not name files matching this glob to
# end with _spec.rb. You can configure this pattern with the --pattern
# option on the command line or in ~/.rspec, .rspec or `.rspec-local`.
#
# The following line is provided for convenience purposes. It has the downside
# of increasing the boot-up time by auto-requiring all files in the support
# directory. Alternatively, in the individual `*_spec.rb` files, manually
# require only the support files necessary.
#
Dir[File.join(File.dirname(__FILE__), 'support', '**', '*.rb')].sort.each { |f| require f }

RSpec::Support::ObjectFormatter.default_instance.max_formatted_output_length = 10_000

# Checks for pending migrations and applies them before tests are run.
# If you are not using ActiveRecord, you can remove these lines.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  puts e.to_s.strip
  exit 1
end
RSpec.configure do |config|
  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  if config.respond_to? :fixture_paths
    config.fixture_paths = Rails.root.join("spec/fixtures")
  else
    config.fixture_path = Rails.root.join("spec/fixtures")
  end

  # RSpec Rails can automatically mix in different behaviours to your tests
  # based on their file location, for example enabling you to call `get` and
  # `post` in specs under `spec/controllers`.
  #
  # You can disable this behaviour by removing the line below, and instead
  # explicitly tag your specs with their type, e.g.:
  #
  #     RSpec.describe UsersController, :type => :controller do
  #       # ...
  #     end
  #
  # The different available types are documented in the features, such as in
  # https://relishapp.com/rspec/rspec-rails/docs
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  # config.filter_gems_from_backtrace("gem name")
end
