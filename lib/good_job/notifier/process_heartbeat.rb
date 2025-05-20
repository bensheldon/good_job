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
        GoodJob::Process.override_connection(connection) do
          GoodJob::Process.cleanup
          @capsule.tracker.register(with_advisory_lock: @advisory_lock_heartbeat)
        end
      end

      def refresh_process
        Rails.application.executor.wrap do
          GoodJob::Process.override_connection(connection) do
            GoodJob::Process.with_logger_silenced do
              @capsule.tracker.renew
            end
          end
        end
      end

      # Deregisters the current process.
      def deregister_process
        GoodJob::Process.override_connection(connection) do
          @capsule.tracker.unregister(with_advisory_lock: @advisory_lock_heartbeat)
        end
      end
    end
  end
end
