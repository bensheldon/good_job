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

require 'github_changelog_generator/task'
GitHubChangelogGenerator::RakeTask.new :changelog do |config|
  config.user = 'bensheldon'
  config.project = 'good_job'
  config.future_release = GoodJob::VERSION
end

def system!(*args)
  system(*args) || abort("\n== Command #{args} failed ==")
end

desc 'Commit version and changelog'
task :commit_version, [:version] do |_t, args|
  version = args[:version]
  if version.blank?
    puts "Pass a version [major|minor|patch|pre|release] or a given version number [x.x.x]:"
    puts "$ bundle exec commit_version[VERSION]"
    return
  end

  puts "\n== Bumping version number =="
  system! "gem bump --no-commit --version #{version}"

  puts "\n== Updating Changelog =="
  system! "bundle exec rake changelog"

  puts "\n== Updating Gemfile.lock version =="
  system! "bundle install"
  system! "bundle exec appraisal install"

  puts "\n== Creating git commit  =="
  system! "git add lib/good_job/version.rb CHANGELOG.md Gemfile.lock gemfiles/*.gemfile.lock"
  system! "git commit -m \"Bump good_job to v#{GoodJob::VERSION}\""
  system! "git tag v#{GoodJob::VERSION}"

  puts "\n== Next steps =="
  puts "Push commit and tag to Github:"
  puts "$ git push --follow-tags"
  puts "\n"
  puts "Push to rubygems"
  puts "$ gem release"
end

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:rspec)

task default: :rspec
