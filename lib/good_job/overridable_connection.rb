# frozen_string_literal: true

module GoodJob # :nodoc:
  # Extends an ActiveRecord odel to override the connection and use
  # an explicit connection that has been removed from the pool.
  module OverridableConnection
    extend ActiveSupport::Concern

    included do
      thread_cattr_accessor :_overridden_connection
    end

    class_methods do
      # Overrides the existing connection method to use the assigned connection
      # @return [ActiveRecord::ConnectionAdapters::AbstractAdapter]
      def connection
        _overridden_connection || super
      end

      # Block interface to assign the connection, yield, then unassign the connection.
      # @param conn [ActiveRecord::ConnectionAdapters::AbstractAdapter]
      # @return [void]
      def override_connection(conn)
        original_conn = _overridden_connection
        self._overridden_connection = conn
        yield
      ensure
        self._overridden_connection = original_conn
      end
    end
  end
end
