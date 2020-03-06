$:.push File.expand_path("lib", __dir__)

# Maintain your gem's version:
require "good_job/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |spec|
  spec.name        = "good_job"
  spec.version     = GoodJob::VERSION
  spec.authors     = ["Ben Sheldon"]
  spec.email       = ["bensheldon@gmail.com"]
  spec.homepage    = "https://github.com/benheldon/good_job"
  spec.summary     = "GoodJob is a minimal postgres based job queue system for Rails"
  spec.description = "GoodJob is a minimal postgres based job queue system for Rails"
  spec.license     = "MIT"

  spec.files = Dir["{lib}/**/*", "bin/good_job", "LICENSE.txt", "README.md"]
  spec.executables = "good_job"

  spec.add_dependency "concurrent-ruby", ">= 1.0.2"
  spec.add_dependency "rails", ">= 5.1.0"
  spec.add_dependency "thor", ">= 0.14.1"
  spec.add_development_dependency "appraisal"
  spec.add_development_dependency "database_cleaner"
  spec.add_development_dependency "gem-release"
  spec.add_development_dependency "github_changelog_generator"
  spec.add_development_dependency "pg"
  spec.add_development_dependency "rspec-rails"
end
