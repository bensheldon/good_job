# frozen_string_literal: true

require "concurrent/array"
require "concurrent/atomic/event"
require "good_job/dedicated_connection"
require "good_job/process_heartbeat"

module GoodJob # :nodoc:
  #
  # Notifiers hook into Postgres LISTEN/NOTIFY functionality to emit and listen for notifications across processes.
  #
  # Notifiers can emit NOTIFY messages through Postgres.
  # A notifier will LISTEN for messages on a {GoodJob::DedicatedConnection}, waiting on the connection's socket.
  # When a message is received, the notifier passes the message to each of its recipients.
  #
  class Notifier
    # Default Postgres channel for LISTEN/NOTIFY
    CHANNEL = 'good_job'
    # Seconds between polls for messages on JRuby, which can't wait on the connection's socket
    WAIT_INTERVAL = 1

    include InstanceRegistry

    # Send a message via Postgres NOTIFY
    # @param message [#to_json]
    def self.notify(message)
      ::GoodJob::Job.connection_pool.with_connection do |connection|
        connection.exec_query <<~SQL.squish
          NOTIFY #{CHANNEL}, #{connection.quote(message.to_json)}
        SQL
      end
    end

    # List of recipients that will receive notifications.
    # @return [Array<#call, Array(Object, Symbol)>]
    attr_reader :recipients

    # @param recipients [Array<#call, Array(Object, Symbol)>]
    # @param enable_listening [true, false]
    # @param connection [GoodJob::DedicatedConnection, nil] Connection to listen on, which the caller starts and shuts down.
    #   When nil, the notifier creates, starts, and shuts down its own connection, and registers the process on it.
    def initialize(*recipients, enable_listening: true, capsule: GoodJob.capsule, connection: nil)
      @recipients = Concurrent::Array.new(recipients)
      @enable_listening = enable_listening
      @listening = Concurrent::Event.new
      @owns_connection = connection.nil?
      @connection = connection || GoodJob::DedicatedConnection.new(reactor: GoodJob::Reactor.new(name: "good_job-notifier"), name: self.class.name)
      GoodJob::ProcessHeartbeat.new(connection: @connection, capsule: capsule) if @owns_connection

      if @enable_listening
        @connection.on_connect { |generation| listen(generation) }
        @connection.on_disconnect { |generation, replaced| unlisten(generation) unless replaced }
        # Other queries on the connection (e.g. the keepalive) can read messages into libpq's buffer without waking the socket watcher.
        @connection.after_task { |generation| receive_buffered_notifications(generation) }
      end

      start
    end

    delegate :running?, to: :@connection

    # Tests whether the notifier is active and has acquired a dedicated database connection.
    # @param timeout [Numeric, nil] Seconds to wait for condition to be true, -1 is forever
    # @return [true, false, nil]
    def connected?(timeout: nil)
      @connection.connected?(timeout: timeout)
    end

    # Tests whether the notifier is listening for new messages.
    # @param timeout [Numeric, nil] Seconds to wait for condition to be true, -1 is forever
    # @return [true, false, nil]
    def listening?(timeout: nil)
      if timeout.nil?
        @listening.set?
      else
        @listening.wait(timeout&.negative? ? nil : timeout)
      end
    end

    delegate :shutdown?, to: :@connection

    # Shut down the notifier, when it owns its connection. A notifier given a +connection:+ (e.g. by a {GoodJob::Capsule})
    # doesn't shut it down: the connection's owner does, and {#shutdown?} reports the connection's state.
    # Use {#shutdown?} to determine whether threads have stopped.
    # @param timeout [Numeric, nil] Seconds to wait for active threads.
    #   * +nil+, the scheduler will trigger a shutdown but not wait for it to complete.
    #   * +-1+, the scheduler will wait until the shutdown is complete.
    #   * A positive number will wait that many seconds before stopping any remaining active threads.
    # @return [void]
    def shutdown(timeout: -1)
      @connection.shutdown(timeout: timeout) if @owns_connection
      shutdown?
    end

    # Restart the notifier, when it owns its connection. A notifier given a +connection:+ is restarted by restarting
    # the connection's owner (e.g. {GoodJob::Capsule#restart}); this does not restart it.
    # When shutdown, start; or shutdown and start.
    # @param timeout [nil, Numeric] Seconds to wait; shares same values as {#shutdown}.
    # @return [void]
    def restart(timeout: -1)
      shutdown(timeout: timeout) unless shutdown?
      start
    end

    private

    def start
      register_instance
      @connection.start if @owns_connection
    end

    def listen(generation)
      ActiveSupport::Notifications.instrument("notifier_listen.good_job") do
        generation.value.execute("LISTEN #{CHANNEL}")
        @listening.set
      end

      raw_connection = generation.value.raw_connection
      if raw_connection.respond_to?(:socket_io)
        generation.watch(raw_connection.socket_io) { receive_notifications(generation) }
      else
        generation.every(WAIT_INTERVAL) { receive_notifications(generation) }
      end
    end

    def unlisten(generation)
      ActiveSupport::Notifications.instrument("notifier_unlisten.good_job") do
        @listening.reset
        generation.value.execute("UNLISTEN *") unless generation.fault?
      end
    end

    # Reads messages already buffered by queries on the connection. JRuby has no buffer to read and polls instead.
    def receive_buffered_notifications(generation)
      raw_connection = generation.value.raw_connection
      return unless raw_connection.respond_to?(:notifies)

      while (notification = raw_connection.notifies)
        receive(notification[:relname], notification[:extra])
      end
    end

    # Reads messages from the socket, and those already buffered by other queries on the connection.
    def receive_notifications(generation)
      raw_connection = generation.value.raw_connection
      if raw_connection.respond_to?(:jdbc_connection)
        raw_connection.execute_query("SELECT 1")
        Array(raw_connection.jdbc_connection.getNotifications).each do |notification|
          receive(notification.getName, notification.getParameter)
        end
      else
        raw_connection.consume_input
        while (notification = raw_connection.notifies)
          receive(notification[:relname], notification[:extra])
        end
      end
    end

    def receive(channel, payload)
      return unless channel == CHANNEL

      ActiveSupport::Notifications.instrument("notifier_notified.good_job", { payload: payload })
      parsed_payload = JSON.parse(payload, symbolize_names: true)
      @recipients.each do |recipient|
        target, method_name = recipient.is_a?(Array) ? recipient : [recipient, :call]
        target.send(method_name, parsed_payload)
      end
    end
  end
end
