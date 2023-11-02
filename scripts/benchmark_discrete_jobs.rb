ENV['GOOD_JOB_EXECUTION_MODE'] = 'external'

require_relative '../demo/config/environment'
require_relative '../lib/good_job'
require 'benchmark/ips'

performer = GoodJob::JobPerformer.new("*")
Benchmark.ips do |x|
  GoodJob::Execution.delete_all
  ActiveJob::Base.queue_adapter.enqueue_all 10_000.times.map { ExampleJob.new }
  GoodJob::Execution.update_all(is_discrete: true)
  x.report("discrete jobs and no errors") do
    performer.next
  end

  GoodJob::Execution.delete_all
  ActiveJob::Base.queue_adapter.enqueue_all 10_000.times.map { ExampleJob.new }
  GoodJob::Execution.update_all(is_discrete: false)
  x.report("undiscrete jobs and no errors") do
    performer.next
  end

  GoodJob::Execution.delete_all
  ActiveJob::Base.queue_adapter.enqueue_all 10_000.times.map { ExampleJob.new(ExampleJob::ERROR_FIVE_TIMES_TYPE) }
  GoodJob::Execution.update_all(is_discrete: true)
  x.report("discrete jobs and 5 errors") do
    performer.next
  end

  GoodJob::Execution.delete_all
  ActiveJob::Base.queue_adapter.enqueue_all 10_000.times.map { ExampleJob.new(ExampleJob::ERROR_FIVE_TIMES_TYPE) }
  GoodJob::Execution.update_all(is_discrete: false)
  x.report("undiscrete jobs and 5 errors") do
    performer.next
  end

  x.compare!
end
