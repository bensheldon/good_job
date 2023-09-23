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
        GoodJob::Process.with_connection(connection) do
          GoodJob::Process.cleanup
          @process = GoodJob::Process.register
        end
      end

      def refresh_process
        Rails.application.executor.wrap do
          GoodJob::Process.with_connection(connection) do
            GoodJob::Process.with_logger_silenced do
              @process&.refresh_if_stale(cleanup: true)
            end
          end
        end
      end

      # Deregisters the current process.
      def deregister_process
        GoodJob::Process.with_connection(connection) do
          @process&.deregister
        end
      end
    end
  end
end
