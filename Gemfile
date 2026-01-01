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
gem 'pg', platforms: [:mri, :windows]

rails_versions = {
  "6.1" => { github: "rails/rails", branch: "6-1-stable" }, # https://github.com/bensheldon/good_job/issues/1280
  "7.0" => { github: "rails/rails", branch: "7-0-stable" }, # Ruby 3.4 requires bigdecimal which rails doesn't declare
  "7.1" => "~> 7.1.0",
  "7.2" => "~> 7.2.0",
  "8.0" => "~> 8.0.0",
  "8.1" => "~> 8.1.0",
  "head" => { github: "rails/rails", branch: "main" },
}
gem 'rails', rails_versions[ENV.fetch("RAILS_VERSION", "8.1")]

# Ruby 4.0 has moved this gem to a bundled gem. Rails 6.1 doesn't declare it.
install_if -> { ENV["RAILS_VERSION"] == "6.1" } do
  gem "benchmark"
end

platforms :ruby do
  gem "bootsnap"
  gem "dotenv-rails"
  gem "foreman"
  gem "gem-release"
  gem "github_changelog_generator", require: false
  gem "rdoc", require: false
  gem "warning"

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
    gem "brakeman"
    gem "easy_translate"
    gem "erb_lint"
    gem "i18n-tasks"
    gem "mdl"
    gem "rubocop"
    gem "rubocop-capybara"
    gem "rubocop-performance"
    gem "rubocop-rails"
    gem "rubocop-rspec"
    gem "rubocop-rspec_rails"
    gem "sorbet"
    gem "sorbet-runtime"
    gem "spoom", require: false
    gem "tapioca", require: false
  end

  group :development, :demo, :production do
    gem "pghero"
    gem "sprockets-rails"
  end

  group :demo, :production do
    gem "skylight"
  end
end
