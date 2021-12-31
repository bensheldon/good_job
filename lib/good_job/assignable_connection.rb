# frozen_string_literal: true
module GoodJob # :nodoc:
  # Extends an ActiveRecord odel to override the connection and use
  # an explicit connection that has been removed from the pool.
  module AssignableConnection
    extend ActiveSupport::Concern

    included do
      thread_cattr_accessor :_connection
    end

    class_methods do
      # Assigns a connection to the model.
      # @param conn [ActiveRecord::ConnectionAdapters::AbstractAdapter]
      # @return [void]
      def connection=(conn)
        self._connection = conn
      end

      # Overrides the existing connection method to use the assigned connection
      # @return [ActiveRecord::ConnectionAdapters::AbstractAdapter]
      def connection
        _connection || super
      end

      # Block interface to assign the connection, yield, then unassign the connection.
      # @param conn [ActiveRecord::ConnectionAdapters::AbstractAdapter]
      # @return [void]
      def with_connection(conn)
        original_conn = _connection
        self.connection = conn
        yield
      ensure
        self._connection = original_conn
      end
    end
  end
end
