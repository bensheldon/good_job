# frozen_string_literal: true

module GoodJob # :nodoc:
  class Notifier # :nodoc:
    # Extends the Notifier to register the process in the database.
    module ProcessRegistration
      extend ActiveSupport::Concern

      included do
        set_callback :listen, :after, :register_process
        set_callback :unlisten, :after, :deregister_process
      end

      # Registers the current process.
      def register_process
        GoodJob::Process.with_connection(connection) do
          GoodJob::Process.cleanup
          @process = GoodJob::Process.register
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
