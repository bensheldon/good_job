# frozen_string_literal: true

module GoodJob # :nodoc:
  class Notifier # :nodoc:
    # Extends the Notifier to register the process in the database.
    module ProcessHeartbeat
      extend ActiveSupport::Concern

      included do
        set_callback :listen, :after, :register_process
        set_callback :tick, :before, :refresh_process
        set_callback :unlisten, :after, :deregister_process
      end

      # Registers the current process.
      def register_process
        @advisory_lock_heartbeat = GoodJob.configuration.advisory_lock_heartbeat
        GoodJob::Process.connection_pool.with_connection do
          @capsule.tracker.cleanup
          @capsule.tracker.register(with_advisory_lock: @advisory_lock_heartbeat, advisory_lock_connection: connection)
          @process_registered = true
        end
      end

      def refresh_process
        Rails.application.executor.wrap do
          GoodJob::Process.with_logger_silenced do
            with_heartbeat_connection { @capsule.tracker.renew }
          end
        end
      end

      # Deregisters the current process.
      def deregister_process
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
end
