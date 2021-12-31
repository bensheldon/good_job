# frozen_string_literal: true
require 'active_support/core_ext/module/attribute_accessors_per_thread'
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
    include ActiveSupport::Callbacks
    define_callbacks :listen, :unlisten

    include Notifier::ProcessRegistration

    # Raised if the Database adapter does not implement LISTEN.
    AdapterCannotListenError = Class.new(StandardError)

    # Default Postgres channel for LISTEN/NOTIFY
    CHANNEL = 'good_job'
    # Defaults for instance of Concurrent::ThreadPoolExecutor
    EXECUTOR_OPTIONS = {
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
    # Seconds to wait if database cannot be connected to
    RECONNECT_INTERVAL = 5
    # Connection errors that will wait {RECONNECT_INTERVAL} before reconnecting
    CONNECTION_ERRORS = %w[
      ActiveRecord::ConnectionNotEstablished
      ActiveRecord::StatementInvalid
      PG::UnableToSend
      PG::Error
    ].freeze

    # @!attribute [r] instances
    #   @!scope class
    #   List of all instantiated Notifiers in the current process.
    #   @return [Array<GoodJob::Notifier>, nil]
    cattr_reader :instances, default: [], instance_reader: false

    # @!attribute [rw] connection
    #   @!scope class
    #   ActiveRecord Connection that has been established for the Notifier.
    #   @return [ActiveRecord::ConnectionAdapters::AbstractAdapter, nil]
    thread_cattr_accessor :connection

    # Send a message via Postgres NOTIFY
    # @param message [#to_json]
    def self.notify(message)
      connection = Execution.connection
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

      create_executor
      listen
    end

    # Tests whether the notifier is active and listening for new messages.
    # @return [true, false, nil]
    def listening?
      @listening.true?
    end

    # Tests whether the notifier is running.
    # @!method running?
    # @return [true, false, nil]
    delegate :running?, to: :executor, allow_nil: true

    # Tests whether the scheduler is shutdown.
    # @!method shutdown?
    # @return [true, false, nil]
    delegate :shutdown?, to: :executor, allow_nil: true

    # Shut down the notifier.
    # This stops the background LISTENing thread.
    # Use {#shutdown?} to determine whether threads have stopped.
    # @param timeout [Numeric, nil] Seconds to wait for active threads.
    #   * +nil+, the scheduler will trigger a shutdown but not wait for it to complete.
    #   * +-1+, the scheduler will wait until the shutdown is complete.
    #   * +0+, the scheduler will immediately shutdown and stop any threads.
    #   * A positive number will wait that many seconds before stopping any remaining active threads.
    # @return [void]
    def shutdown(timeout: -1)
      return if executor.nil? || executor.shutdown?

      executor.shutdown if executor.running?

      if executor.shuttingdown? && timeout # rubocop:disable Style/GuardClause
        executor_wait = timeout.negative? ? nil : timeout
        executor.kill unless executor.wait_for_termination(executor_wait)
      end
    end

    # Restart the notifier.
    # When shutdown, start; or shutdown and start.
    # @param timeout [nil, Numeric] Seconds to wait; shares same values as {#shutdown}.
    # @return [void]
    def restart(timeout: -1)
      shutdown(timeout: timeout) if running?
      create_executor
      listen
    end

    # Invoked on completion of ThreadPoolExecutor task
    # @!visibility private
    # @return [void]
    def listen_observer(_time, _result, thread_error)
      return if thread_error.is_a? AdapterCannotListenError

      if thread_error
        GoodJob._on_thread_error(thread_error)
        ActiveSupport::Notifications.instrument("notifier_notify_error.good_job", { error: thread_error })

        connection_error = CONNECTION_ERRORS.any? do |error_string|
          error_class = error_string.safe_constantize
          next unless error_class

          thread_error.is_a? error_class
        end
      end

      return if shutdown?

      listen(delay: connection_error ? RECONNECT_INTERVAL : 0)
    end

    private

    attr_reader :executor

    def create_executor
      @executor = Concurrent::ThreadPoolExecutor.new(EXECUTOR_OPTIONS)
    end

    def listen(delay: 0)
      future = Concurrent::ScheduledTask.new(delay, args: [@recipients, executor, @listening], executor: @executor) do |thr_recipients, thr_executor, thr_listening|
        with_connection do
          begin
            run_callbacks :listen do
              ActiveSupport::Notifications.instrument("notifier_listen.good_job") do
                connection.execute("LISTEN #{CHANNEL}")
              end
              thr_listening.make_true
            end

            ActiveSupport::Dependencies.interlock.permit_concurrent_loads do
              while thr_executor.running?
                wait_for_notify do |channel, payload|
                  next unless channel == CHANNEL

                  ActiveSupport::Notifications.instrument("notifier_notified.good_job", { payload: payload })
                  parsed_payload = JSON.parse(payload, symbolize_names: true)
                  thr_recipients.each do |recipient|
                    target, method_name = recipient.is_a?(Array) ? recipient : [recipient, :call]
                    target.send(method_name, parsed_payload)
                  end
                end
              end
            end
          end
        ensure
          run_callbacks :unlisten do
            thr_listening.make_false
            ActiveSupport::Notifications.instrument("notifier_unlisten.good_job") do
              connection.execute("UNLISTEN *")
            end
          end
        end
      end

      future.add_observer(self, :listen_observer)
      future.execute
    end

    def with_connection
      self.connection = Execution.connection_pool.checkout.tap do |conn|
        Execution.connection_pool.remove(conn)
      end
      connection.execute("SET application_name = #{connection.quote(self.class.name)}")

      yield
    ensure
      connection&.disconnect!
      self.connection = nil
    end

    def wait_for_notify
      raw_connection = connection.raw_connection
      if raw_connection.respond_to?(:wait_for_notify)
        raw_connection.wait_for_notify(WAIT_INTERVAL) do |channel, _pid, payload|
          yield(channel, payload)
        end
      else
        sleep WAIT_INTERVAL
      end
    end
  end
end
