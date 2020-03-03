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

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  spec.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  spec.executables = "good_job"

  spec.add_dependency "concurrent-ruby"
  spec.add_dependency "rails"
  spec.add_dependency "thor"
  spec.add_development_dependency "database_cleaner"
  spec.add_development_dependency "pg"
  spec.add_development_dependency "rspec-rails"
end
