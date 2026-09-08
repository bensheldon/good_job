# frozen_string_literal: true

# Compares thread and fiber execution against a dedicated PostgreSQL database.
#
# Requires CRuby 3.2+, Rails 7.1+, and Async >= 2.24 in the development bundle.
# Setup refuses a nonempty database. Use a database reserved for this benchmark.
#
#   bundle install
#   createdb -h localhost good_job_fiber_benchmark
#   export GOOD_JOB_BENCHMARK_DATABASE_URL=postgresql://localhost/good_job_fiber_benchmark
#   bundle exec ruby scripts/benchmark_fiber_execution.rb --prepare
#   bundle exec ruby scripts/benchmark_fiber_execution.rb > tmp/fiber-benchmark.jsonl
#
# Defaults: 250 jobs per scenario, one warmup and three measured runs, each in
# a fresh worker process. Both modes use concurrency 25 and pool 30; fibers
# also run with pool 5. Both use Rails fiber isolation and disabled reloading.
#
# Workloads: sleep, local Net::HTTP, Ruby CPU work, OpenSSL PBKDF2, and a
# transaction that holds a connection while sleeping. Most use skiplocked;
# advisory-lock and transaction scenarios measure connection pinning.
#
# JSONL output includes throughput, runtime versions, revision and file hashes,
# pool size, sampled thread/connection peaks, errors, retries, duplicate starts,
# and reactor delay (excess time in a 1 ms fiber sleep).
#
# Samples are taken every 10 ms and may miss peaks. Counts include monitoring
# connections and utility threads. Exclude warmups when comparing runs, and
# keep the revision and diff with results. Errors or duplicate executions fail
# the benchmark. These synthetic workloads do not predict production latency.
require 'json'
require 'open3'
require 'optparse'
require 'uri'
require 'rbconfig'
require 'etc'

options = { jobs: 250, repetitions: 3 }
OptionParser.new do |parser|
  parser.on('--jobs COUNT', Integer) { |value| options[:jobs] = value }
  parser.on('--repetitions COUNT', Integer) { |value| options[:repetitions] = value }
  parser.on('--prepare') { options[:prepare] = true }
  parser.on('--worker JSON') { |value| options[:worker] = JSON.parse(value, symbolize_names: true) }
end.parse!
abort 'Counts must be positive' unless options[:jobs].positive? && options[:repetitions].positive?
url = ENV.fetch('GOOD_JOB_BENCHMARK_DATABASE_URL') { abort 'Set GOOD_JOB_BENCHMARK_DATABASE_URL to a dedicated database ending in _benchmark' }
database_name = URI.parse(url).path.delete_prefix('/')
abort 'Benchmark database must end in _benchmark' unless database_name.match?(/\A[a-zA-Z0-9_]+_benchmark\z/)

if options[:worker] || options[:prepare]
  run = options[:worker] || { mode: 'threads', pool: 30 }
  ENV['DATABASE_URL'] = url
  ENV['RAILS_ENV'] = 'test'
  ENV['RAILS_MAX_THREADS'] = run[:pool].to_s
  ENV['GOOD_JOB_EXECUTION_MODE'] = 'external'
  ENV['GOOD_JOB_ENABLE_CRON'] = 'false'
  ENV['GOOD_JOB_FIBERS'] = run[:mode] == 'fibers' ? '25' : 'false'
  require_relative '../demo/config/application'
  Rails.application.config.cache_classes = true
  Rails.application.config.active_support.isolation_level = :fiber
  Rails.application.initialize!
  ActiveRecord::Base.establish_connection(url: url, pool: run[:pool])
  if options[:prepare]
    abort 'Refusing to load schema into a nonempty database' if ActiveRecord::Base.connection_pool.with_connection { |connection| connection.tables.any? }
    load File.expand_path('../demo/db/schema.rb', __dir__)
    exit
  end

  require 'net/http'
  require 'openssl'
  require 'securerandom'
  require 'timeout'
  GoodJob.logger = Logger.new(File::NULL)
  ActiveRecord::Base.logger = Logger.new(File::NULL)
  ActiveJob::Base.logger = Logger.new(File::NULL)
  GoodJob.configuration.options[:lock_strategy] = run.fetch(:lock).to_sym
  abort 'Run --prepare: lock_type migration is required for this comparison' unless GoodJob::Job.column_names.include?('lock_type')
  GoodJob.preserve_job_records = true
  RUNS = Concurrent::Array.new
  HEARTBEATS = Concurrent::Array.new
  ERRORS = Concurrent::Array.new
  GoodJob.on_thread_error = ->(error) { ERRORS << "#{error.class}: #{error.message}" }

  class FiberBenchmarkJob < ActiveJob::Base
    self.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)

    def perform(workload, port)
      RUNS << job_id
      if Fiber.scheduler
        Fiber.schedule do
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          sleep 0.001
          HEARTBEATS << [Process.clock_gettime(Process::CLOCK_MONOTONIC) - started - 0.001, 0].max
        end
      end
      case workload
      when 'sleep' then sleep 0.02
      when 'http'
        response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/work"))
        raise "HTTP #{response.code}" unless response.code == '200'
      when 'cpu'
        value = 1
        50_000.times { |i| value = (value * 31 + i) % 1_000_003 }
      when 'native'
        OpenSSL::PKCS5.pbkdf2_hmac('password', 'salt', 20_000, 32, 'sha256')
      when 'transaction'
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          connection.transaction do
            connection.execute('SELECT 1')
            sleep 0.02
          end
        end
      end
      ActiveRecord::Base.connection_pool.with_connection { |connection| connection.execute('SELECT 1') }
    end
  end

  run_id = SecureRandom.uuid
  queue = "fiber-benchmark-#{run_id}"
  ids = []
  scheduler = nil
  monitor = nil
  sampling = true
  sampler = nil
  begin
    jobs = Array.new(run.fetch(:jobs)) { FiberBenchmarkJob.new(run.fetch(:workload), run[:port]).tap { |job| job.queue_name = queue } }
    ids = jobs.map(&:job_id)
    FiberBenchmarkJob.queue_adapter.enqueue_all(jobs)
    scheduler = GoodJob::Scheduler.new(GoodJob::JobPerformer.new(queue), max_threads: 25, fibers: run[:mode] == 'fibers' ? 25 : nil)
    monitor = PG.connect(url)
    peaks = { threads: 0, pool_connections: 0, postgres_connections: 0 }
    sampler = Thread.new do
      while sampling
        peaks[:threads] = [peaks[:threads], Thread.list.count(&:alive?)].max
        peaks[:pool_connections] = [peaks[:pool_connections], ActiveRecord::Base.connection_pool.stat[:connections]].max
        connections = monitor.exec('SELECT count(*) FROM pg_stat_activity WHERE datname = current_database()').getvalue(0, 0).to_i
        peaks[:postgres_connections] = [peaks[:postgres_connections], connections].max
        sleep 0.01
      end
    end
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    25.times { scheduler.create_thread }
    Timeout.timeout(120) do
      loop do
        remaining = ActiveRecord::Base.connection_pool.with_connection { GoodJob::Job.where(id: ids, finished_at: nil).count }
        break if remaining.zero?
        sleep 0.01
      end
    end
    scheduler.shutdown(timeout: 10)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    sampling = false
    sampler.join
    executions = GoodJob::Execution.where(active_job_id: ids)
    errors = executions.where.not(error: nil).count + ERRORS.size
    duplicates = RUNS.size - RUNS.uniq.size
    puts JSON.generate(run.merge(
      run_id: run_id, elapsed_seconds: elapsed, jobs_per_second: ids.size / elapsed,
      measured_at: Time.now.utc.iso8601,
      peak_threads: peaks[:threads], peak_pool_connections: peaks[:pool_connections],
      peak_postgres_connections: peaks[:postgres_connections], errors: errors,
      retries: executions.count - ids.size, duplicate_executions: duplicates,
      max_reactor_delay_seconds: HEARTBEATS.max,
      ruby: RUBY_DESCRIPTION, rails: Rails.version, async: Gem.loaded_specs['async']&.version&.to_s,
      net_http: Gem.loaded_specs['net-http']&.version&.to_s,
      openssl: Gem.loaded_specs['openssl']&.version&.to_s, openssl_library: OpenSSL::OPENSSL_VERSION,
      pg: PG::VERSION, postgres: monitor.server_version,
      os: RbConfig::CONFIG['host_os'], architecture: RbConfig::CONFIG['host_cpu'],
      logical_processors: Etc.nprocessors,
      revision: Open3.capture2('git', 'rev-parse', 'HEAD').first.strip,
      script_sha256: OpenSSL::Digest::SHA256.file(__FILE__).hexdigest,
      tracked_diff_sha256: OpenSSL::Digest::SHA256.hexdigest(Open3.capture2('git', 'diff', 'HEAD').first)
    ))
    abort 'Unexpected errors or duplicate executions' unless errors.zero? && duplicates.zero? && RUNS.size == ids.size
  ensure
    sampling = false
    sampler&.join(5)
    scheduler&.shutdown(timeout: 0)
    GoodJob.shutdown(timeout: 0)
    monitor&.close
    GoodJob::Execution.where(active_job_id: ids).delete_all
    GoodJob::Job.where(id: ids).delete_all
  end
  exit
end

# A separate HTTP server process keeps server work off the job reactor.
server_input, server_output, server_error, server_thread = Open3.popen3(RbConfig.ruby, '-rwebrick', '-e', <<~'RUBY')
  server = WEBrick::HTTPServer.new(BindAddress: '127.0.0.1', Port: 0, Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
  server.mount_proc('/work') { |_request, response| sleep 0.02; response.body = 'ok' }
  trap('TERM') { server.shutdown }
  STDOUT.sync = true
  puts server.listeners.first.addr[1]
  server.start
RUBY
begin
  port = Integer(server_output.gets)
  cases = %w[sleep http cpu native].product([['threads', 30], ['fibers', 30], ['fibers', 5]]).map do |workload, (mode, pool)|
    { workload: workload, mode: mode, pool: pool, lock: 'skiplocked' }
  end
  cases.concat([['threads', 30], ['fibers', 30], ['fibers', 5]].map { |mode, pool| { workload: 'sleep', mode: mode, pool: pool, lock: 'advisory' } })
  cases << { workload: 'transaction', mode: 'fibers', pool: 5, lock: 'skiplocked' }
  cases.each do |scenario|
    (0..options[:repetitions]).each do |repetition|
      run = scenario.merge(jobs: options[:jobs], port: port, repetition: repetition, warmup: repetition.zero?)
      warn "Benchmark: #{run}"
      output, status = Open3.capture2e(RbConfig.ruby, __FILE__, '--worker', JSON.generate(run))
      abort output unless status.success?
      result = output.lines.reverse.find { |line| line.start_with?('{') }
      abort "Missing benchmark result: #{output}" unless result
      puts result
      STDOUT.flush
    end
  end
ensure
  Process.kill('TERM', server_thread.pid) if server_thread.alive?
  server_thread.join
  [server_input, server_output, server_error].each(&:close)
end
