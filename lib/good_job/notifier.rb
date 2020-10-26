require 'concurrent/atomic/atomic_boolean'

module GoodJob # :nodoc:
  #
  # Notifiers hook into Postgres LISTEN/NOTIFY functionality to emit and listen for notifications across processes.
  #
  # Notifiers can emit NOTIFY messages through Postgres.
  # A notifier will LISTEN for messages by creating a background thread that runs in an instance of +Concurrent::ThreadPoolExecutor+.
  # When a message is received, the notifier passes the message to each of its recipients.
  #
  class Notifier
    AdapterCannotListenError = Class.new(StandardError)

    # Default Postgres channel for LISTEN/NOTIFY
    CHANNEL = 'good_job'.freeze
    # Defaults for instance of Concurrent::ThreadPoolExecutor
    POOL_OPTIONS = {
      name: name,
      min_threads: 0,
      max_threads: 1,
      auto_terminate: true,
      idletime: 60,
      max_queue: 1,
      fallback_policy: :discard,
    }.freeze
    # Seconds to block while LISTENing for a message
    WAIT_INTERVAL = 1

    # @!attribute [r] instances
    #   @!scope class
    #   List of all instantiated Notifiers in the current process.
    #   @return [array<GoodJob:Adapter>]
    cattr_reader :instances, default: [], instance_reader: false

    # Send a message via Postgres NOTIFY
    # @param message [#to_json]
    def self.notify(message)
      connection = ActiveRecord::Base.connection
      connection.exec_query <<~SQL.squish
        NOTIFY #{CHANNEL}, #{connection.quote(message.to_json)}
      SQL
    end

    # List of recipients that will receive notifications.
    # @return [Array<#call, Array(Object, Symbol)>]
    attr_reader :recipients

    # @param recipients [Array<#call, Array(Object, Symbol)>]
    def initialize(*recipients)
      @recipients = Concurrent::Array.new(recipients)
      @listening = Concurrent::AtomicBoolean.new(false)

      self.class.instances << self

      create_pool
      listen
    end

    # Tests whether the notifier is active and listening for new messages.
    # @return [true, false, nil]
    def listening?
      @listening.true?
    end

    # Restart the notifier.
    # When shutdown, start; or shutdown and start.
    # @param wait [Boolean] Wait for background thread to finish
    # @return [void]
    def restart(wait: true)
      shutdown(wait: wait)
      create_pool
      listen
    end

    # Shut down the notifier.
    # This stops the background LISTENing thread.
    # If +wait+ is +true+, the notifier will wait for background thread to shutdown.
    # If +wait+ is +false+, this method will return immediately even though threads may still be running.
    # Use {#shutdown?} to determine whether threads have stopped.
    # @param wait [Boolean] Wait for actively executing threads to finish
    # @return [void]
    def shutdown(wait: true)
      return unless @pool.running?

      @pool.shutdown
      @pool.wait_for_termination if wait
    end

    # Tests whether the notifier is shutdown.
    # @return [true, false, nil]
    def shutdown?
      !@pool.running?
    end

    # Invoked on completion of ThreadPoolExecutor task
    # @!visibility private
    # @return [void]
    def listen_observer(_time, _result, thread_error)
      return if thread_error.is_a? AdapterCannotListenError

      if thread_error
        GoodJob.on_thread_error.call(thread_error) if GoodJob.on_thread_error.respond_to?(:call)
        ActiveSupport::Notifications.instrument("notifier_notify_error.good_job", { error: thread_error })
      end

      listen unless shutdown?
    end

    private

    def create_pool
      @pool = Concurrent::ThreadPoolExecutor.new(POOL_OPTIONS)
    end

    def listen
      future = Concurrent::Future.new(args: [@recipients, @pool, @listening], executor: @pool) do |recipients, pool, listening|
        with_listen_connection do |conn|
          ActiveSupport::Notifications.instrument("notifier_listen.good_job") do
            conn.async_exec("LISTEN #{CHANNEL}").clear
          end

          ActiveSupport::Dependencies.interlock.permit_concurrent_loads do
            while pool.running?
              listening.make_true
              conn.wait_for_notify(WAIT_INTERVAL) do |channel, _pid, payload|
                listening.make_false
                next unless channel == CHANNEL

                ActiveSupport::Notifications.instrument("notifier_notified.good_job", { payload: payload })
                parsed_payload = JSON.parse(payload, symbolize_names: true)
                recipients.each do |recipient|
                  target, method_name = recipient.is_a?(Array) ? recipient : [recipient, :call]
                  target.send(method_name, parsed_payload)
                end
              end
              listening.make_false
            end
          end
        ensure
          listening.make_false
          ActiveSupport::Notifications.instrument("notifier_unlisten.good_job") do
            conn.async_exec("UNLISTEN *").clear
          end
        end
      end

      future.add_observer(self, :listen_observer)
      future.execute
    end

    def with_listen_connection
      ar_conn = ActiveRecord::Base.connection_pool.checkout.tap do |conn|
        ActiveRecord::Base.connection_pool.remove(conn)
      end
      pg_conn = ar_conn.raw_connection
      raise AdapterCannotListenError unless pg_conn.respond_to? :wait_for_notify

      pg_conn.async_exec("SET application_name = #{pg_conn.escape_identifier(self.class.name)}").clear
      yield pg_conn
    ensure
      ar_conn&.disconnect!
    end
  end
end
