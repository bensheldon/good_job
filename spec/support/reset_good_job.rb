# frozen_string_literal: true

THREAD_ERRORS = Concurrent::Array.new

ActiveSupport.on_load :active_record do
  ActiveRecord::ConnectionAdapters::AbstractAdapter.set_callback :checkout, :after, lambda {
    thread_name = Thread.current.name || Thread.current.object_id
    sql = "SET application_name = #{quote(thread_name)}"

    # Necessary because of https://github.com/rails/rails/pull/51083/files#r1496720821
    # JDBC raw connections don't have #query, fall back to exec_query (safe after checkout)
    if @raw_connection.respond_to?(:query)
      @raw_connection.query(sql)
    else
      exec_query(sql, "Set application name")
    end
  }
end

RSpec.configure do |config|
  config.around do |example|
    GoodJob.preserve_job_records = true

    PgLock.current_database.advisory_lock.owns.all?(&:unlock) if PgLock.advisory_lock.owns.any?
    PgLock.current_database.advisory_lock.others.each(&:unlock!) if PgLock.advisory_lock.others.any?
    expect(PgLock.current_database.advisory_lock.count).to eq(0), "Existing advisory locks BEFORE test run"

    GoodJob::CurrentThread.reset
    THREAD_ERRORS.clear
    GoodJob.on_thread_error = lambda do |exception|
      THREAD_ERRORS << [Thread.current.name, exception, exception.backtrace]
    end

    example.run

    expect(THREAD_ERRORS).to be_empty
  end

  config.after do
    GoodJob.shutdown(timeout: -1)

    executables = [].concat(
      GoodJob::Capsule.instances,
      GoodJob::SharedExecutor.instances,
      GoodJob::CronManager.instances,
      GoodJob::Notifier.instances,
      GoodJob::Poller.instances,
      GoodJob::Scheduler.instances,
      GoodJob::CronManager.instances
    )
    GoodJob._shutdown_all(executables, timeout: -1)

    GoodJob::CapsuleTracker.instances.each do |tracker|
      expect(tracker.locks).to eq 0
    end
    GoodJob::CapsuleTracker.instances.clear

    expect(GoodJob::Notifier.instances).to all be_shutdown
    GoodJob::Notifier.instances.clear

    expect(GoodJob::Poller.instances).to all be_shutdown
    GoodJob::Poller.instances.clear

    expect(GoodJob::CronManager.instances).to all be_shutdown
    GoodJob::CronManager.instances.clear

    expect(GoodJob::Scheduler.instances).to all be_shutdown
    GoodJob::Scheduler.instances.clear

    expect(GoodJob::Capsule.instances).to all be_shutdown
    GoodJob::Capsule.instances.clear

    # always make sure there is a capsule; unstub it first if necessary
    RSpec::Mocks.space.proxy_for(GoodJob::Capsule).reset
    GoodJob.capsule = GoodJob::Capsule.new

    own_locks = PgLock.current_database.advisory_lock.owns
    if own_locks.any?
      puts "There are #{own_locks.count} advisory locks still open by the current database connection AFTER test run."

      puts "\nAdvisory locked executions:"
      GoodJob::Job.advisory_locked.owns_advisory_locked.each do |execution|
        puts "  - Execution ID: #{execution.id} / Active Job ID: #{execution.active_job_id}"
      end

      puts "\nAdvisory Locks:"
      own_locks.includes(:pg_stat_activity).all.each do |pg_lock| # rubocop:disable Rails/FindEach
        puts "  - #{pg_lock.pid}: #{pg_lock.pg_stat_activity&.application_name}"
      end

      puts "\nCurrent connections:"
      PgStatActivity.all.each do |pg_stat_activity| # rubocop:disable Rails/FindEach
        puts "  - #{pg_stat_activity.pid}: #{pg_stat_activity.application_name}"
      end
    end

    expect(PgLock.current_database.advisory_lock.owns.count).to eq(0), "Existing owned advisory locks AFTER test run"

    other_locks = PgLock.current_database.advisory_lock.others
    if other_locks.any?
      puts "There are #{other_locks.count} advisory locks owned by other connections still open AFTER test run."

      puts "\nAdvisory locked executions:"
      GoodJob::Job.advisory_locked.each do |execution|
        puts "  - Execution ID: #{execution.id} / Active Job ID: #{execution.active_job_id} / Locked by: #{execution[:pid]}"
      end

      puts "\nAdvisory Locks:"
      other_locks.includes(:pg_stat_activity).all.each do |pg_lock| # rubocop:disable Rails/FindEach
        puts "  - #{pg_lock.pid}: #{pg_lock.pg_stat_activity&.application_name}"
      end

      puts "\nCurrent connections:"
      PgStatActivity.all.each do |pg_stat_activity| # rubocop:disable Rails/FindEach
        puts "  - #{pg_stat_activity.pid}: #{pg_stat_activity.application_name}"
      end
    end
    expect(PgLock.current_database.advisory_lock.others.count).to eq(0), "Existing others advisory locks AFTER test run"

    GoodJob.configuration.instance_variable_set(:@_in_webserver, nil)
  end
end

module PostgresXidExtension
  def initialize_type_map(map = type_map)
    if respond_to?(:register_class_with_limit, true)
      register_class_with_limit map, 'xid', ActiveRecord::Type::String # OID 28
    else
      # Rails 7 defines statically
      # https://github.com/rails/rails/commit/d79fb963603658117fd1d639976c375ea2a8ada3
      self.class.send :register_class_with_limit, map, 'xid', ActiveRecord::Type::String # OID 28
    end

    super
  end
end

ActiveSupport.on_load :active_record do
  ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend PostgresXidExtension
end

class PgStatActivity < GoodJob::BaseRecord
  self.table_name = 'pg_stat_activity'
  self.primary_key = 'datid'
end

class PgLock < GoodJob::BaseRecord
  self.table_name = 'pg_locks'
  self.primary_key = 'objid'

  belongs_to :pg_stat_activity, primary_key: :pid, foreign_key: :pid

  scope :current_database, -> { joins("JOIN pg_database ON pg_database.oid = pg_locks.database").where("pg_database.datname = current_database()") }
  scope :advisory_lock, -> { where(locktype: 'advisory') }
  scope :owns, -> { where('pid = pg_backend_pid()') }
  scope :others, -> { where('pid != pg_backend_pid()') }

  def self.count_locks_for(connection)
    connection.execute(<<~SQL.squish).first['count'].to_i
      SELECT count(*)
      FROM pg_locks
      WHERE
        database = (SELECT oid FROM pg_database WHERE datname = current_database())
        AND pid = pg_backend_pid()
        AND locktype = 'advisory'
    SQL
  end

  # Returns an array of hashes with classid, objid, objsubid, pid, granted for each
  # advisory lock held by the connection. Multiple rows for the same classid/objid
  # indicate re-entrant (double) lock acquisition.
  def self.advisory_lock_details_for(connection)
    connection.execute(<<~SQL.squish).to_a
      SELECT classid, objid, objsubid, pid, granted
      FROM pg_locks
      WHERE
        database = (SELECT oid FROM pg_database WHERE datname = current_database())
        AND pid = pg_backend_pid()
        AND locktype = 'advisory'
      ORDER BY classid, objid
    SQL
  end

  def self.debug_own_locks(connection)
    count = count_locks_for(connection)
    return false if count.zero?

    output = []
    output << "There are #{count} advisory locks still open by the current database connection."

    adopt_connection(GoodJob::Job, connection) do
      GoodJob::Job.owns_advisory_locked.each.with_index do |job, index|
        output << "\nAdvisory locked GoodJob::Job:" if index.zero?
        output << "  - Job ID: #{job.id} / Active Job ID: #{job.active_job_id}"
      end
    end

    adopt_connection(GoodJob::BatchRecord, connection) do
      GoodJob::BatchRecord.owns_advisory_locked.each.with_index do |batch, index|
        output << "\nAdvisory locked GoodJob::Batch:" if index.zero?
        output << "  - BatchRecord ID: #{batch.id}"
      end
    end

    adopt_connection(GoodJob::Process, connection) do
      GoodJob::Process.owns_advisory_locked.each.with_index do |process, index|
        output << "\nAdvisory locked GoodJob::Process:" if index.zero?
        output << "  - Process ID: #{process.id}"
      end
    end

    output << "\nAdvisory Locks:"
    PgLock.current_database.advisory_lock.owns.includes(:pg_stat_activity).all.each do |pg_lock| # rubocop:disable Rails/FindEach
      output << "  - #{pg_lock.pid}: #{pg_stat_activity&.application_name}"
    end

    output.join("\n")
  end

  # Temporarily adopts +conn+ as the active connection for +model_class+'s pool
  # within the block, so that AR queries on that model use the given connection.
  def self.adopt_connection(model_class, conn)
    pool = model_class.connection_pool
    if pool.instance_variable_defined?(:@leases) # Rails 8.0+
      lease = pool.__send__(:connection_lease)
      prev_conn = lease.connection
      prev_sticky = lease.sticky
      lease.connection = conn
      lease.sticky = true
      begin
        yield
      ensure
        lease.connection = prev_conn
        lease.sticky = prev_sticky
      end
    else # Rails 6.1–7.x
      ctx = if defined?(ActiveSupport::IsolatedExecutionState)
              ActiveSupport::IsolatedExecutionState.context
            else
              Thread.current
            end
      cache_key = pool.__send__(:connection_cache_key, ctx)
      prev = pool.instance_variable_get(:@thread_cached_conns)[cache_key]
      pool.instance_variable_get(:@thread_cached_conns)[cache_key] = conn
      begin
        yield
      ensure
        if prev
          pool.instance_variable_get(:@thread_cached_conns)[cache_key] = prev
        else
          pool.instance_variable_get(:@thread_cached_conns).delete(cache_key)
        end
      end
    end
  end

  def unlock
    query = <<~SQL.squish
      SELECT pg_advisory_unlock(($1::bigint << 32) + $2::bigint) AS unlocked
    SQL

    binds = [
      ActiveRecord::Relation::QueryAttribute.new('classid', classid, ActiveRecord::Type::String.new),
      ActiveRecord::Relation::QueryAttribute.new('objid', objid, ActiveRecord::Type::String.new),
    ]
    self.class.lease_connection.exec_query(GoodJob::Job.pg_or_jdbc_query(query), 'PgLock Advisory Unlock', binds).first['unlocked']
  end

  def unlock!
    query = <<~SQL.squish
      SELECT pg_terminate_backend(#{self[:pid]}) AS terminated
    SQL
    self.class.lease_connection.exec_query(GoodJob::Job.pg_or_jdbc_query(query), 'PgLock Terminate Backend Lock', []).first['terminated']
  end
end
