# frozen_string_literal: true
source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby_version = ENV.fetch('GEMFILE_RUBY_VERSION', nil)
ruby ruby_version if ruby_version

# Declare your gem's dependencies in good_job.gemspec.
# Bundler will treat runtime dependencies like base dependencies, and
# development dependencies will be added by default to the :development group.
gemspec

# Declare any dependencies that are still in development here instead of in
# your gemspec. These might include edge Rails or gems from your path or
# Git. Remember to move these dependencies to your gemspec before releasing
# your gem to rubygems.org.

gem 'activerecord-jdbcpostgresql-adapter', platforms: [:jruby]
gem 'appraisal', github: "bensheldon/appraisal", branch: "fix-bundle-env" # https://github.com/thoughtbot/appraisal/pull/174
gem 'matrix'
gem 'nokogiri'
gem 'pg', platforms: [:mri, :mingw, :x64_mingw]
gem 'rails'

platforms :ruby do
  gem "activerecord-explain-analyze"
  gem "pry-byebug"

  group :lint do
    gem 'easy_translate'
    gem "erb_lint"
    gem 'i18n-tasks'
    gem "mdl"
    gem "rubocop"
    gem "rubocop-performance"
    gem "rubocop-rails"
    gem "rubocop-rspec"
  end
end
