$LOAD_PATH.push File.expand_path("lib", __dir__)

# Maintain your gem's version:
require "good_job/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |spec|
  spec.name        = "good_job"
  spec.version     = GoodJob::VERSION
  spec.summary     = "A multithreaded, Postgres-based ActiveJob backend for Ruby on Rails"
  spec.description = "A multithreaded, Postgres-based ActiveJob backend for Ruby on Rails"

  spec.license     = "MIT"
  spec.authors     = ["Ben Sheldon"]
  spec.email       = ["bensheldon@gmail.com"]
  spec.homepage    = "https://github.com/benheldon/good_job"
  spec.metadata = {
    "bug_tracker_uri"   => "https://github.com/bensheldon/good_job/issues",
    "changelog_uri"     => "https://github.com/bensheldon/good_job/blob/master/CHANGELOG.md",
    "documentation_uri" => "https://rdoc.info/github/bensheldon/good_job",
    "homepage_uri"      => spec.homepage,
    "source_code_uri"   => "https://github.com/bensheldon/good_job",
  }

  spec.files = Dir["lib/**/*", "LICENSE.txt", "README.md"]
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

  spec.required_ruby_version = ">= 2.4.0"

  spec.add_dependency "concurrent-ruby", ">= 1.0.2"
  spec.add_dependency "pg", ">= 1.0.0"
  spec.add_dependency "rails", ">= 5.1.0"
  spec.add_dependency "thor", ">= 0.14.1"

  spec.add_development_dependency "appraisal"
  spec.add_development_dependency "database_cleaner"
  spec.add_development_dependency "foreman"
  spec.add_development_dependency "gem-release"
  spec.add_development_dependency "github_changelog_generator"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "rspec-rails"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "rubocop-performance"
  spec.add_development_dependency "rubocop-rails"
  spec.add_development_dependency "rubocop-rspec"
end
