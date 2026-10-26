# frozen_string_literal: true

module GoodJob # :nodoc:
  #
  # Registers the process in the database while a {GoodJob::DedicatedConnection} is connected.
  # When the advisory lock heartbeat is enabled, the process record is advisory locked on that connection.
  #
  class ProcessHeartbeat
    # Seconds between refreshes of the process record (it is only written when stale)
    INTERVAL = 1

    # @param connection [GoodJob::DedicatedConnection]
    # @param capsule [GoodJob::Capsule]
    def initialize(connection:, capsule: GoodJob.capsule)
      @capsule = capsule
      @process_registered = false

      # A replacement connection doesn't re-register; the advisory lock heartbeat doesn't replace connections.
      connection.on_connect { |generation, replacing| register_process(generation.value) unless replacing }
      connection.on_disconnect { |generation, replaced| deregister_process(generation.value) unless replaced }
      connection.every(INTERVAL) { |generation| refresh_process(generation.value) }
    end

    # Registers the current process.
    # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter] Dedicated connection to hold the advisory lock.
    def register_process(connection)
      @advisory_lock_heartbeat = GoodJob.configuration.advisory_lock_heartbeat
      GoodJob::Process.connection_pool.with_connection do
        @capsule.tracker.cleanup
        @capsule.tracker.register(with_advisory_lock: @advisory_lock_heartbeat, advisory_lock_connection: connection)
        @process_registered = true
      end
    end

    # Refreshes the process record on the dedicated connection, and cleans up inactive processes after a refresh.
    # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter] Dedicated connection.
    def refresh_process(connection)
      GoodJob::Process.with_logger_silenced do
        refreshed = @capsule.tracker.renew(connection: connection)
        with_heartbeat_connection { GoodJob::Process.cleanup } if refreshed
      end
    end

    # Deregisters the current process.
    # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter] Dedicated connection holding the advisory lock.
    def deregister_process(connection)
      return unless @process_registered

      # Acquire a pooled connection before the tracker mutex: job threads need that
      # mutex to finish their registrations and return their connections to the pool.
      with_heartbeat_connection(retry_checkout: true) do
        @capsule.tracker.unregister(with_advisory_lock: @advisory_lock_heartbeat, advisory_lock_connection: connection)
        @process_registered = false
      end
    end

    private

    def with_heartbeat_connection(retry_checkout: false)
      acquired = false
      begin
        GoodJob::Process.connection_pool.with_connection do
          acquired = true
          yield
        end
      rescue ActiveRecord::ConnectionTimeoutError
        raise if acquired

        # Keep the dedicated advisory connection alive until deregistration can
        # transfer remaining jobs to heartbeat liveness. Refreshes can wait a tick.
        retry if retry_checkout
      end
    end
  end
end
