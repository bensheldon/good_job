# frozen_string_literal: true

# Compares the dequeue query with and without priority ordering
# (`dequeue_query_priority`) for each `dequeue_query_sort`, using the SQL that
# GoodJob generates for the :advisory and :skiplocked lock strategies.
#
# Seeds a table with finished history and unfinished jobs (half due now, half
# scheduled ahead), then reports the median server-side execution time from
# EXPLAIN ANALYZE and the index each query uses.
#
# To run:
#   bundle exec ruby scripts/benchmark_dequeue_priority.rb
#
# Options (environment variables):
#   FINISHED=1000000 UNFINISHED=100000 QUEUES=10 RUNS=15
#
# This deletes all GoodJob records in the configured database.

ENV['GOOD_JOB_EXECUTION_MODE'] = 'external'

require_relative '../demo/config/environment'
require_relative '../lib/good_job'

finished = Integer(ENV.fetch('FINISHED', 1_000_000))
unfinished = Integer(ENV.fetch('UNFINISHED', 100_000))
queues = Integer(ENV.fetch('QUEUES', 10))
runs = Integer(ENV.fetch('RUNS', 15))

connection = GoodJob::Job.lease_connection

puts "Seeding #{finished} finished and #{unfinished} unfinished jobs across #{queues} queues..."
GoodJob::Job.delete_all
connection.execute(<<~SQL.squish)
  INSERT INTO good_jobs (id, active_job_id, queue_name, priority, serialized_params, job_class, executions_count,
                         created_at, updated_at, scheduled_at, performed_at, finished_at)
  SELECT gen_random_uuid(), gen_random_uuid(), 'queue' || floor(random() * #{queues})::int, 0, '{}'::jsonb, 'ExampleJob', 1,
         t, t, t, t, t + interval '1 second'
  FROM (SELECT now() - interval '7 days' + (g * interval '7 days' / #{finished}) AS t FROM generate_series(1, #{finished}) g) history
SQL
connection.execute(<<~SQL.squish)
  INSERT INTO good_jobs (id, active_job_id, queue_name, priority, serialized_params, job_class, executions_count,
                         created_at, updated_at, scheduled_at)
  SELECT gen_random_uuid(), gen_random_uuid(), 'queue' || floor(random() * #{queues})::int, 0, '{}'::jsonb, 'ExampleJob', 0,
         t, t, CASE WHEN random() < 0.5 THEN t ELSE now() + (random() * interval '2 hours') END
  FROM (SELECT now() - interval '1 hour' + (g * interval '1 hour' / #{unfinished}) AS t FROM generate_series(1, #{unfinished}) g) pending
SQL
connection.execute('VACUUM ANALYZE good_jobs')

def candidate_sql(lock_strategy, queue_string, select_limit: nil)
  parsed_queues = GoodJob::Job.queue_parser(queue_string)
  query = GoodJob::Job.queue_string(queue_string).unfinished
  query = query.where(locked_by_id: nil) if lock_strategy == :skiplocked
  query = query.dequeueing_ordered(parsed_queues).only_scheduled.exclude_paused.limit(1)

  if lock_strategy == :skiplocked
    query.select(:id).lock("FOR NO KEY UPDATE SKIP LOCKED").to_sql
  else
    query.advisory_lock(select_limit: select_limit).to_sql
  end
end

def explain(connection, sql)
  plan = nil
  connection.transaction do
    plan = connection.select_values("EXPLAIN (ANALYZE, FORMAT TEXT) #{sql}")
    raise ActiveRecord::Rollback
  end
  connection.execute('SELECT pg_advisory_unlock_all()')
  time = plan.grep(/Execution Time/).first[/[\d.]+/].to_f
  scans = plan.join("\n").scan(/(?:Index Only Scan|Index Scan|Bitmap Index Scan) (?:Backward )?(?:using|on) (\w+)/).flatten
  index = (scans - %w[index_good_job_settings_on_key good_jobs_pkey]).first || 'Seq Scan'
  [time, index]
end

queue_strings = ['queue3', 'queue1,queue2,queue3', '*']
dequeue_query_sorts = %i[created_at scheduled_at]
dequeue_query_priorities = [true, false]

results = []
%i[advisory skiplocked].each do |lock_strategy|
  queue_strings.each do |queue_string|
    dequeue_query_sorts.each do |dequeue_query_sort|
      dequeue_query_priorities.each do |dequeue_query_priority|
        GoodJob.configuration = GoodJob::Configuration.new({ dequeue_query_sort: dequeue_query_sort, dequeue_query_priority: dequeue_query_priority })
        sql = candidate_sql(lock_strategy, queue_string)
        samples = Array.new(runs) { explain(connection, sql) }
        times = samples.map(&:first).sort
        results << [lock_strategy, queue_string, dequeue_query_sort, dequeue_query_priority, times[times.size / 2], samples.last.last]
      end
    end
  end
end

puts
puts "Median of #{runs} runs (EXPLAIN ANALYZE execution time), PostgreSQL #{connection.select_value('SHOW server_version')}"
puts
puts "| lock strategy | queues | dequeue_query_sort | priority | median ms | index |"
puts "|---|---|---|---|---:|---|"
results.each do |lock_strategy, queue_string, sort, priority, median, index|
  puts "| #{lock_strategy} | #{queue_string} | #{sort} | #{priority} | #{format('%.3f', median)} | #{index} |"
end
