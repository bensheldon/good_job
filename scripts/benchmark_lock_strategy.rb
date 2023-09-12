ENV['GOOD_JOB_EXECUTION_MODE'] = 'external'

require_relative '../spec/test_app/config/environment'
require_relative '../lib/good_job'
require 'benchmark/ips'

advisory_lock_performer = GoodJob::JobPerformer.new("*")
row_lock_performer = GoodJob::JobRowLockPerformer.new("*")
Benchmark.ips do |x|
  GoodJob::Execution.delete_all
  ActiveJob::Base.queue_adapter.enqueue_all 10_000.times.map { ExampleJob.new }
  GoodJob::Execution.update_all(is_discrete: true)
  x.report("Advisory Locked jobs and no errors") do
    advisory_lock_performer.next
  end

  GoodJob::Execution.delete_all
  ActiveJob::Base.queue_adapter.enqueue_all 10_000.times.map { ExampleJob.new }
  GoodJob::Execution.update_all(is_discrete: true)
  GoodJob.capsule.tracker.register do
    x.report("Row Locked jobs and no errors") do
      row_lock_performer.next
    end
  end

  x.compare!
end
