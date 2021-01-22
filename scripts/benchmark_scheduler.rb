#
# $ bundle exec ruby scripts/benchmark_scheduler.rb
#
require 'memory_profiler'
require_relative '../lib/good_job'

class Performer
  def name
    ''
  end

  def next
    sleep 0.1
  end
end

scheduler = GoodJob::Scheduler.new(Performer.new, max_threads: 5)

report = MemoryProfiler.report do
  10_000.times { scheduler.create_thread }
end

report.pretty_print
