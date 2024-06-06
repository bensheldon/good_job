# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby_version_path = File.join(File.dirname(__FILE__), '.ruby-version')
if File.exist?(ruby_version_path)
  # .ruby-version may not always contain a complete/valid 3+ identifier Ruby version
  ruby_version_contents = File.read(ruby_version_path).strip
  ruby(ruby_version_contents) if ruby_version_contents.match?(%r{\A\d+\.\d+\.\d+})
end
# Declare your gem's dependencies in good_job.gemspec.
# Bundler will treat runtime dependencies like base dependencies, and
# development dependencies will be added by default to the :development group.
gemspec

# Declare any dependencies that are still in development here instead of in
# your gemspec. These might include edge Rails or gems from your path or
# Git. Remember to move these dependencies to your gemspec before releasing
# your gem to rubygems.org.

gem 'activerecord-jdbcpostgresql-adapter', platforms: [:jruby]
gem 'appraisal'
gem 'matrix'
gem 'nokogiri'
gem 'pg', platforms: [:mri, :mingw, :x64_mingw]
gem 'rack', '~> 2.2'
gem 'rails'
gem 'rspec-rails', github: "rspec/rspec-rails", branch: "main"

platforms :ruby do
  gem "bootsnap"
  gem "dotenv-rails"
  gem "foreman"
  gem "gem-release"
  gem "github_changelog_generator", require: false
  gem "net-imap", require: false
  gem "net-pop", require: false
  gem "net-smtp", require: false

  group :debug do
    gem "activerecord-explain-analyze", require: false
    gem "benchmark-ips"
    gem "debug"
    gem "memory_profiler"
    gem "rack-mini-profiler"
    gem "rbtrace"
    gem "stackprof"
  end

  group :lint do
    gem "easy_translate", require: false
    gem "erb_lint", require: false
    gem "i18n-tasks", require: false
    gem "mdl", require: false
    gem "rubocop", require: false
    gem "rubocop-capybara", require: false
    gem "rubocop-performance", require: false
    gem "rubocop-rails", require: false
    gem "rubocop-rspec", require: false
    gem "rubocop-rspec_rails", require: false
    gem "sorbet", require: false
    gem "sorbet-runtime", require: false
    gem "spoom", require: false
    gem "tapioca", require: false
  end

  group :demo, :production do
    gem "skylight"
  end
end
