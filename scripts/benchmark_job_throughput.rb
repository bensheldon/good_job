# To run:
# bundle exec ruby scripts/benchmark_example.rb
#

ENV['GOOD_JOB_EXECUTION_MODE'] = 'external'

require_relative '../spec/test_app/config/environment'
require_relative '../lib/good_job'
require 'benchmark/ips'
require 'pry'

booleans = [true, false]
priorities = (1..10).to_a
scheduled_minutes = (-60..60).to_a

GoodJob::Job.delete_all
puts "Seeding database"
jobs_data = Array.new(10_000) do |i|
  puts "Initializing seed record ##{i}" if (i % 1_000).zero?
  {
    queue_name: 'default',
    priority: priorities.sample,
    scheduled_at: booleans.sample ? scheduled_minutes.sample.minutes.ago : nil,
    created_at: 90.minutes.ago,
    updated_at: 90.minutes.ago,
    finished_at: booleans.sample ? scheduled_minutes.sample.minutes.ago : nil,
    serialized_params: {},
  }
end
puts "Inserting seed records into the database...\n"
GoodJob::Job.insert_all(jobs_data)

# ActiveRecord::Base.connection.execute('SET enable_seqscan = OFF')
# puts GoodJob::Job.unfinished.priority_ordered.only_scheduled(use_coalesce: true).limit(1).advisory_lock.explain(analyze: true)
# exit!

Benchmark.ips do |x|
  x.report("with priority") do
    GoodJob::Job.unfinished.priority_ordered.only_scheduled(use_coalesce: true).limit(1).with_advisory_lock do |good_jobs|
      # good_jobs.first&.destroy!
    end
  end

  x.report("without priority") do
    GoodJob::Job.unfinished.only_scheduled(use_coalesce: true).limit(1).with_advisory_lock do |good_jobs|
      # good_jobs.first&.destroy!
    end
  end

  x.compare!
end
