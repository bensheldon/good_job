# To run:
# bundle exec ruby scripts/benchmark_job_throughput.rb
#

ENV['GOOD_JOB_EXECUTION_MODE'] = 'external'

require_relative '../demo/config/environment'
require_relative '../lib/good_job'
require 'benchmark/ips'

Benchmark.ips do |x|
  x.report("session") do
    Rails.application.executor.wrap do
      GoodJob::Job.advisory_lock_key("the-key", function: "pg_advisory_lock") do
        GoodJob::Job.count
      end
    end
  end

  x.report("xact with commit") do
    Rails.application.executor.wrap do
      GoodJob::Job.transaction do
        GoodJob::Job.advisory_lock_key("the-key", function: "pg_advisory_xact_lock") do
          puts GoodJob::Job.advisory_locked_key?("the-key")
          GoodJob::Job.count
        end
      end
    end
  end

  x.report("xact with rollback") do
    Rails.application.executor.wrap do
      GoodJob::Job.transaction do
        GoodJob::Job.advisory_lock_key("the-key", function: "pg_advisory_xact_lock") do
          GoodJob::Job.count
          raise ActiveRecord::Rollback
        end
      end
    end
  end

  x.compare!
end
