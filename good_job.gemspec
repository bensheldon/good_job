require_paths = ["lib", "engine/lib"]
require_paths.each do |require_path|
  $LOAD_PATH.push File.expand_path(require_path, __dir__)
end

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
  spec.homepage    = "https://github.com/bensheldon/good_job"
  spec.metadata = {
    "bug_tracker_uri"   => "https://github.com/bensheldon/good_job/issues",
    "changelog_uri"     => "https://github.com/bensheldon/good_job/blob/master/CHANGELOG.md",
    "documentation_uri" => "https://rdoc.info/github/bensheldon/good_job",
    "homepage_uri"      => spec.homepage,
    "source_code_uri"   => "https://github.com/bensheldon/good_job",
  }

  spec.files = Dir[
    "engine/**/*",
    "lib/**/*",
    "README.md",
    "CHANGELOG.md",
    "LICENSE.txt",
  ]
  spec.require_paths = require_paths
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

  spec.required_ruby_version = ">= 2.5.0"

  spec.add_dependency "activejob", ">= 5.2.0"
  spec.add_dependency "activerecord", ">= 5.2.0"
  spec.add_dependency "concurrent-ruby", ">= 1.0.2"
  spec.add_dependency "railties", ">= 5.2.0"
  spec.add_dependency "thor", ">= 0.14.1"
  spec.add_dependency "zeitwerk", ">= 2.0"

  spec.add_development_dependency "benchmark-ips", "2.8.4" # https://github.com/evanphx/benchmark-ips/pull/115
  spec.add_development_dependency "capybara"
  spec.add_development_dependency "database_cleaner"
  spec.add_development_dependency "dotenv"
  spec.add_development_dependency "foreman"
  spec.add_development_dependency "gem-release"
  spec.add_development_dependency "github_changelog_generator"
  spec.add_development_dependency "kramdown"
  spec.add_development_dependency "kramdown-parser-gfm"
  spec.add_development_dependency "pry-rails"
  spec.add_development_dependency "puma"
  spec.add_development_dependency "rspec-rails"
  spec.add_development_dependency "selenium-webdriver"
  spec.add_development_dependency "sigdump"
  spec.add_development_dependency "yard"
  spec.add_development_dependency "yard-activesupport-concern"
end
