#
# $ bundle exec ruby scripts/benchmark_scheduler.rb
#
require_relative '../spec/test_app/config/environment'
require_relative '../lib/good_job'
require 'memory_profiler'
require 'pry'

MAX_CACHE = 10_000
MAX_THREADS = 0
JOBS_SIZE = 20_000

class CustomPerformer < GoodJob::JobPerformer
  def name
    'script'
  end

  def next
    sleep 0.1
  end

  def next?(_state)
    true
  end

  def next_at(**_options)
    []
  end
end

scheduler = GoodJob::Scheduler.new(CustomPerformer.new("*"), max_threads: MAX_THREADS, max_cache: MAX_CACHE)

report = MemoryProfiler.report do
  JOBS_SIZE.times { scheduler.create_thread({ scheduled_at: Time.current + 100_000 }) }
end

report.pretty_print
