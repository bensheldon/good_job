module PostgresXidExtension
  def initialize_type_map(map = type_map)
    register_class_with_limit map, 'xid', ActiveRecord::Type::String # OID 28
    super(map)
  end
end

PostgresNoticeError = Class.new(StandardError)

ActiveSupport.on_load :active_record do
  ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend PostgresXidExtension

  ActiveRecord::ConnectionAdapters::AbstractAdapter.set_callback :checkout, :before, lambda { |conn|
    raw_connection = conn.raw_connection
    next unless raw_connection.respond_to? :set_notice_receiver

    raw_connection.set_notice_receiver do |result|
      raise PostgresNoticeError, result.error_message
    end
  }
end

class PgLock < ActiveRecord::Base
  self.table_name = 'pg_locks'
  self.primary_key = 'objid'

  scope :advisory_lock, -> { where(locktype: 'advisory') }
  scope :owns, -> { where('pid = pg_backend_pid()') }
  scope :others, -> { where('pid != pg_backend_pid()') }

  def unlock
    where_sql = <<~SQL.squish
      pg_advisory_unlock((?::bigint << 32) + ?::bigint)
    SQL
    self.class.unscoped.exists?([where_sql, classid, objid])
  end

  def unlock!
    where_sql = <<~SQL.squish
      pg_terminate_backend(?)
    SQL
    self.class.unscoped.exists?([where_sql, pid])
  end
end

RSpec.configure do |config|
  config.before do
    PgLock.advisory_lock.owns.each(&:unlock) if PgLock.advisory_lock.owns.count > 0
    PgLock.advisory_lock.others.each(&:unlock!) if PgLock.advisory_lock.others.count > 0
    expect(PgLock.advisory_lock.count).to eq(0), "Existing advisory locks BEFORE test run"
  end

  config.after do
    expect(PgLock.owns.advisory_lock.count).to eq(0), "Existing owned advisory locks AFTER test run"
    expect(PgLock.others.advisory_lock.count).to eq(0), "Existing others advisory locks AFTER test run"
  end
end
