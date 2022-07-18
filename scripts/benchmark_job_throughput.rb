# To run:
# bundle exec ruby scripts/benchmark_job_throughput.rb
#

ENV['GOOD_JOB_EXECUTION_MODE'] = 'external'

require_relative '../spec/test_app/config/environment'
require_relative '../lib/good_job'
require 'benchmark/ips'
require 'pry'

booleans = [true, false]
priorities = (1..10).to_a
scheduled_minutes = (-60..60).to_a
queue_names = ["one", "two", "three"]

GoodJob::Execution.delete_all
puts "Seeding database"
executions_data = Array.new(10_000) do |i|
  puts "Initializing seed record ##{i}" if (i % 1_000).zero?
  {
    queue_name: queue_names.sample,
    priority: priorities.sample,
    scheduled_at: booleans.sample ? scheduled_minutes.sample.minutes.ago : nil,
    created_at: 90.minutes.ago,
    updated_at: 90.minutes.ago,
    finished_at: booleans.sample ? scheduled_minutes.sample.minutes.ago : nil,
    serialized_params: {},
  }
end
puts "Inserting seed records into the database...\n"
GoodJob::Execution.insert_all(executions_data)

# ActiveRecord::Base.connection.execute('SET enable_seqscan = OFF')

Benchmark.ips do |x|
x.report("without sorts") do
    GoodJob::Execution.unfinished.only_scheduled.limit(1).with_advisory_lock do |executions|
      # executions.first&.destroy!
    end
  end

  x.report("sort by priority only") do
    GoodJob::Execution.unfinished.priority_ordered.only_scheduled.limit(1).with_advisory_lock do |executions|
      # executions.first&.destroy!
    end
  end

  x.report("sort by creation only") do
    GoodJob::Execution.unfinished.creation_ordered.only_scheduled.limit(1).with_advisory_lock do |executions|
      # executions.first&.destroy!
    end
  end

  x.report("sort by priority and creation") do
    GoodJob::Execution.unfinished.priority_ordered.creation_ordered.only_scheduled.limit(1).with_advisory_lock do |executions|
      # executions.first&.destroy!
    end
  end

  x.report("sort by ordered queues only") do
    GoodJob::Execution.unfinished.queue_ordered(%w{one two three}).creation_ordered.only_scheduled.limit(1).with_advisory_lock do |executions|
      # executions.first&.destroy!
    end
  end

  x.report("sort by ordered queues and creation") do
    GoodJob::Execution.unfinished.queue_ordered(%w{one two three}).creation_ordered.only_scheduled.limit(1).with_advisory_lock do |executions|
      # executions.first&.destroy!
    end
  end

  x.report("sort by ordered queues, priority, and creation") do
    GoodJob::Execution.unfinished.queue_ordered(%w{one two three}).priority_ordered.creation_ordered.only_scheduled.limit(1).with_advisory_lock do |executions|
      # executions.first&.destroy!
    end
  end

  x.compare!
end
