#
# $ bundle exec ruby scripts/benchmark_job_lock_time.rb
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
jobs_data = Array.new(1_000) do |i|
  {
    queue_name: 'default',
    priority: priorities.sample,
    scheduled_at: booleans.sample ? scheduled_minutes.sample.minutes.ago : nil,
    created_at: Time.current,
    updated_at: Time.current,
    serialized_params: {},
  }
end
GoodJob::Job.insert_all(jobs_data)

ActiveRecord::Base.connection.execute('SET enable_seqscan = OFF')
puts GoodJob::Job.unfinished.priority_ordered.only_scheduled(use_coalesce: false).limit(1).explain(analyze: true)
exit!

Benchmark.ips do |x|
  x.report("with OR") do
    GoodJob::Job.unfinished.priority_ordered.only_scheduled(use_coalesce: false).limit(1).with_advisory_lock do |good_jobs|
      nil # nothing
    end
  end
  x.report("with COALESCE") do
    GoodJob::Job.unfinished.priority_ordered.only_scheduled(use_coalesce: true).limit(1).with_advisory_lock do |good_jobs|
      nil # nothing
    end
  end

  x.compare!
end

