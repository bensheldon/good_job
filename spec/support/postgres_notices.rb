# frozen_string_literal: true

#
# Raise an exception when Postgres writes a notice to $stderr
#
POSTGRES_NOTICES = Concurrent::Array.new

# Attach on (re)connect rather than on checkout: calling `raw_connection` on
# the adapter marks it dirty, which prevents Rails from reconnecting it.
module PostgresNoticeReceiver
  def configure_connection
    super
    # Rails < 7.1 stores the PG::Connection in @connection
    pg_connection = @raw_connection || @connection
    return unless pg_connection.respond_to?(:set_notice_receiver)

    pg_connection.set_notice_receiver do |result|
      Rails.logger.warn(result.error_message.strip)
      POSTGRES_NOTICES << result.error_message
    end
  end
end

ActiveSupport.on_load :active_record do
  # Rails < 7.0 has no :active_record_postgresqladapter load hook
  require "active_record/connection_adapters/postgresql_adapter"
  ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend PostgresNoticeReceiver

  ActiveRecord::ConnectionAdapters::AbstractAdapter.set_callback :checkin, :before, lambda { |conn|
    count = PgLock.count_locks_for(conn)
    next if count.zero?

    warning = "Connection returned to pool with #{count} advisory locks (conn.object_id=#{conn.object_id})"
    $stdout.puts warning
    Rails.logger.warn(warning)
    POSTGRES_NOTICES << warning
  }
end

RSpec.configure do |config|
  config.around do |example|
    POSTGRES_NOTICES.clear
    example.run
    expect(POSTGRES_NOTICES).to be_empty
  end
end
