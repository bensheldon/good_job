# frozen_string_literal: true

require_relative "lib/good_job/version"

Gem::Specification.new do |spec|
  spec.name        = "good_job"
  spec.version     = GoodJob::VERSION
  spec.summary     = "A multithreaded, Postgres-based ActiveJob backend for Ruby on Rails"
  spec.description = "A multithreaded, Postgres-based ActiveJob backend for Ruby on Rails"

  spec.license     = "MIT"
  spec.authors     = ["Ben Sheldon"]
  spec.email       = ["bensheldon@gmail.com"]
  spec.homepage    = "https://github.com/bensheldon/good_job"
  spec.metadata = {
    "bug_tracker_uri"   => "https://github.com/bensheldon/good_job/issues",
    "changelog_uri"     => "https://github.com/bensheldon/good_job/blob/master/CHANGELOG.md",
    "documentation_uri" => "https://rubydoc.info/gems/good_job",
    "homepage_uri"      => spec.homepage,
    "source_code_uri"   => "https://github.com/bensheldon/good_job",
    "rubygems_mfa_required" => "true",
  }

  spec.files = Dir[
    "app/**/*",
    "config/**/*",
    "lib/**/*",
    "README.md",
    "CHANGELOG.md",
    "LICENSE.txt",
  ]
  spec.require_paths = ["lib"]
  spec.bindir = "exe"
  spec.executables = %w[good_job]

  spec.extra_rdoc_files = Dir["README.md", "CHANGELOG.md", "LICENSE.txt"]
  spec.rdoc_options += [
    "--title", "GoodJob - a multithreaded, Postgres-based ActiveJob backend for Ruby on Rails",
    "--main", "README.md",
    "--line-numbers",
    "--inline-source",
    "--quiet"
  ]

  spec.required_ruby_version = ">= 2.6.0"

  spec.add_runtime_dependency "activejob", ">= 6.0.0"
  spec.add_runtime_dependency "activerecord", ">= 6.0.0"
  spec.add_runtime_dependency "concurrent-ruby", ">= 1.0.2"
  spec.add_runtime_dependency "fugit", ">= 1.1"
  spec.add_runtime_dependency "railties", ">= 6.0.0"
  spec.add_runtime_dependency "thor", ">= 0.14.1"

  spec.add_development_dependency "benchmark-ips"
  spec.add_development_dependency "capybara"
  spec.add_development_dependency "kramdown"
  spec.add_development_dependency "kramdown-parser-gfm"
  spec.add_development_dependency "pry-rails"
  spec.add_development_dependency "puma"
  spec.add_development_dependency "rspec-rails"
  spec.add_development_dependency "selenium-webdriver"
  spec.add_development_dependency "webrick"
  spec.add_development_dependency "yard"
  spec.add_development_dependency "yard-activesupport-concern"
end
