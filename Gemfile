# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

# Declare your gem's dependencies in good_job.gemspec.
# Bundler will treat runtime dependencies like base dependencies, and
# development dependencies will be added by default to the :development group.
gemspec

# Declare any dependencies that are still in development here instead of in
# your gemspec. These might include edge Rails or gems from your path or
# Git. Remember to move these dependencies to your gemspec before releasing
# your gem to rubygems.org.

gem 'activerecord-jdbcpostgresql-adapter', platforms: [:jruby]
gem 'appraisal', github: 'thoughtbot/appraisal', branch: 'main'
gem 'matrix'
gem 'nokogiri'
gem 'pg', platforms: [:mri, :mingw, :x64_mingw]
gem 'rack', '~> 2.2'
gem 'rails'

platforms :ruby do
  gem "activerecord-explain-analyze", require: false
  gem "dotenv"
  gem "foreman"
  gem "gem-release"
  gem "github_changelog_generator", require: false
  gem "net-imap", require: false
  gem "net-pop", require: false
  gem "net-smtp", require: false
  gem "pry-byebug"
  gem "rack-mini-profiler"
  gem "rbtrace"
  gem "stackprof"
  gem "tapioca", require: false, group: :development
  gem "vernier", github: "jhawthorn/vernier", branch: "main"

  group :lint do
    gem "easy_translate"
    gem "erb_lint"
    gem "i18n-tasks"
    gem "mdl"
    gem "rubocop"
    gem "rubocop-performance"
    gem "rubocop-rails"
    gem "rubocop-rspec"
    gem "sorbet"
    gem "sorbet-runtime"
    gem "spoom", require: false
  end
end
