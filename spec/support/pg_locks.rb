module PostgresXidExtension
  def initialize_type_map(map = type_map)
    register_class_with_limit map, 'xid', ActiveRecord::Type::String # OID 28
    super(map)
  end
end

ActiveSupport.on_load :active_record do
  ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend PostgresXidExtension
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
end

RSpec.configure do |config|
  config.before do
    PgLock.advisory_lock.each(&:unlock) if PgLock.advisory_lock.count > 0
    expect(PgLock.advisory_lock.count).to eq(0), "Existing advisory locks BEFORE test run"
  end

  config.after do
    expect(PgLock.owns.advisory_lock.count).to eq(0), "Existing owned advisory locks AFTER test run"
    expect(PgLock.others.advisory_lock.count).to eq(0), "Existing others advisory locks AFTER test run"
  end
end
