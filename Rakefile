begin
  require 'bundler/setup'
rescue LoadError
  puts 'You must `gem install bundler` and `bundle install` to run rake tasks'
end

require_relative "lib/good_job/version"

require 'rdoc/task'

RDoc::Task.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.title    = 'GoodJob'
  rdoc.options << '--line-numbers'
  rdoc.rdoc_files.include('README.md')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

require 'bundler/gem_tasks'

def system!(*args)
  system(*args) || abort("\n== Command #{args} failed ==")
end

desc 'Commit version and changelog'
task :commit_version, [:version_bump] do |_t, args|
  version_bump = args[:version_bump]
  if version_bump.nil?
    puts "Pass a version [major|minor|patch|pre|release] or a given version number [x.x.x]:"
    puts "$ bundle exec rake commit_version[VERSION_BUMP]"
    exit(1)
  end

  puts "\n== Bumping version number =="
  system! "gem bump --no-commit --version #{version_bump}"

  puts "\n== Reloading GoodJob::VERSION"
  load File.expand_path('lib/good_job/version.rb', __dir__)
  puts GoodJob::VERSION

  puts "\n== Updating Changelog =="
  system! ENV, "bundle exec github_changelog_generator --user bensheldon --project good_job --future-release v#{GoodJob::VERSION}"

  puts "\n== Updating Gemfile.lock version =="
  system! "bundle install"
  system! "bundle exec appraisal install"

  puts "\n== Creating git commit  =="
  system! "git add lib/good_job/version.rb CHANGELOG.md Gemfile.lock gemfiles/*.gemfile.lock"
  system! "git commit -m \"Bump good_job to v#{GoodJob::VERSION}\""
  system! "git tag v#{GoodJob::VERSION}"

  puts "\n== Next steps =="
  puts "Run the following commands:\n\n"
  puts "  1. Push commit and tag to Github:"
  puts "    $ git push origin --follow-tags"
  puts "  2. Push to Rubygems.org:"
  puts "    $ gem release`"
end

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:rspec)

task default: :rspec
