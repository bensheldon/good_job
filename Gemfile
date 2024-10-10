# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby_version_path = File.join(File.dirname(__FILE__), '.ruby-version')
if File.exist?(ruby_version_path)
  # .ruby-version may not always contain a complete/valid 3+ identifier Ruby version
  ruby_version_contents = File.read(ruby_version_path).strip
  ruby(ruby_version_contents) if ruby_version_contents.match?(%r{\d+\.\d+\.\d+})
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
gem 'pg', platforms: [:mri, :mingw, :x64_mingw]
gem 'rack', '~> 3.1'

rails_versions = {
  "6.1" => { github: "rails/rails", branch: "6-1-stable" }, # https://github.com/bensheldon/good_job/issues/1280
  "7.0" => "~> 7.0.1", # Ruby 3.1 requires Rails 7.0.1+
  "7.1" => "~> 7.1.0",
  "7.2" => "~> 7.2.0",
  "8.0" => "~> 8.0.0.a",
  "head" => { github: "rails/rails", branch: "main" },
}
gem 'rails', rails_versions[ENV.fetch("RAILS_VERSION", nil)]

platforms :ruby do
  gem "bootsnap"
  gem "dotenv-rails"
  gem "foreman"
  gem "gem-release"
  gem "github_changelog_generator", require: false

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

  group :demo, :production do
    gem "skylight"
  end
end
