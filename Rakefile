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
end

desc 'Commit version and changelog'
task :commit_version do
  `git add lib/good_job/version.rb CHANGELOG.md`
  `git commit -m "Bump good_job to v#{GoodJob::VERSION}"`
  `git tag v#{GoodJob::VERSION}`
  puts "Don't forget to push to Github"
end

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:rspec)

task default: :rspec
