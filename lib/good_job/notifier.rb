# frozen_string_literal: true

require 'active_support/core_ext/module/attribute_accessors_per_thread'
require 'concurrent/atomic/atomic_boolean'
require "good_job/notifier/process_heartbeat"

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
    define_callbacks :listen, :tick, :unlisten

    include ProcessHeartbeat

    # Default Postgres channel for LISTEN/NOTIFY
    CHANNEL = 'good_job'
    # Seconds to block while LISTENing for a message
    WAIT_INTERVAL = 1
    # Seconds to wait if database cannot be connected to
    RECONNECT_INTERVAL = 5
    # Number of consecutive connection errors before reporting an error
    CONNECTION_ERRORS_REPORTING_THRESHOLD = 6

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
    cattr_reader :instances, default: Concurrent::Array.new, instance_reader: false

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
    # @param enable_listening [true, false]
    # @param executor [Concurrent::ExecutorService]
    def initialize(*recipients, enable_listening: true, executor: Concurrent.global_io_executor)
      @recipients = Concurrent::Array.new(recipients)
      @enable_listening = enable_listening
      @executor = executor

      @mutex = Mutex.new
      @shutdown_event = Concurrent::Event.new.tap(&:set)
      @running = Concurrent::AtomicBoolean.new(false)
      @connected = Concurrent::Event.new
      @listening = Concurrent::Event.new
      @connection_errors_count = Concurrent::AtomicFixnum.new(0)
      @connection_errors_reported = Concurrent::AtomicBoolean.new(false)
      @enable_listening = enable_listening
      @task = nil

      start
      self.class.instances << self
    end

    def running?
      @executor.running? && @running.true?
    end

    # Tests whether the notifier is active and has acquired a dedicated database connection.
    # @param timeout [Numeric, nil] Seconds to wait for condition to be true, -1 is forever
    # @return [true, false, nil]
    def connected?(timeout: nil)
      if timeout.nil?
        @connected.set?
      else
        @connected.wait(timeout == -1 ? nil : timeout)
      end
    end

    # Tests whether the notifier is listening for new messages.
    # @param timeout [Numeric, nil] Seconds to wait for condition to be true, -1 is forever
    # @return [true, false, nil]
    def listening?(timeout: nil)
      if timeout.nil?
        @listening.set?
      else
        @listening.wait(timeout == -1 ? nil : timeout)
      end
    end

    def shutdown?
      @shutdown_event.set?
    end

    # Shut down the notifier.
    # This stops the background LISTENing thread.
    # Use {#shutdown?} to determine whether threads have stopped.
    # @param timeout [Numeric, nil] Seconds to wait for active threads.
    #   * +nil+, the scheduler will trigger a shutdown but not wait for it to complete.
    #   * +-1+, the scheduler will wait until the shutdown is complete.
    #   * A positive number will wait that many seconds before stopping any remaining active threads.
    # @return [void]
    def shutdown(timeout: -1)
      synchronize do
        @running.make_false

        if @executor.shutdown? || @task&.complete?
          # clean up in the even the executor is killed
          @connected.reset
          @listening.reset
          @shutdown_event.set
        else
          @shutdown_event.wait(timeout == -1 ? nil : timeout) unless timeout.nil?
          @connected.reset if @shutdown_event.set?
        end
        @shutdown_event.set?
      end
    end

    # Restart the notifier.
    # When shutdown, start; or shutdown and start.
    # @param timeout [nil, Numeric] Seconds to wait; shares same values as {#shutdown}.
    # @return [void]
    def restart(timeout: -1)
      synchronize do
        shutdown(timeout: timeout) unless @shutdown_event.set?
        start
      end
    end

    # Invoked on completion of ThreadPoolExecutor task
    # @!visibility private
    # @return [void]
    def listen_observer(_time, _result, thread_error)
      if thread_error
        ActiveSupport::Notifications.instrument("notifier_notify_error.good_job", { error: thread_error })

        connection_error = CONNECTION_ERRORS.any? do |error_string|
          error_class = error_string.safe_constantize
          next unless error_class

          thread_error.is_a? error_class
        end

        if connection_error
          @connection_errors_count.increment
          if @connection_errors_reported.false? && @connection_errors_count.value >= CONNECTION_ERRORS_REPORTING_THRESHOLD
            @connected.reset
            GoodJob._on_thread_error(thread_error)
            @connection_errors_reported.make_true
          end
        else
          GoodJob._on_thread_error(thread_error)
        end
      end

      if @running.true?
        create_listen_task(delay: connection_error ? RECONNECT_INTERVAL : 0)
      else
        @shutdown_event.set
      end
    end

    private

    def start
      synchronize do
        return if @running.true?

        @running.make_true
        @shutdown_event.reset
        create_listen_task(delay: 0)
      end
    end

    def create_listen_task(delay: 0)
      @task = Concurrent::ScheduledTask.new(delay, args: [@recipients, @running, @executor, @enable_listening, @connected, @listening], executor: @executor) do |thr_recipients, thr_running, thr_executor, thr_enable_listening, thr_connected, thr_listening|
        with_connection do
          thr_connected.set

          begin
            Rails.application.executor.wrap do
              run_callbacks :listen do
                if thr_enable_listening
                  ActiveSupport::Notifications.instrument("notifier_listen.good_job") do
                    connection.execute("LISTEN #{CHANNEL}")
                    thr_listening.set
                  end
                end
              end
            end

            while thr_executor.running? && thr_running.true?
              run_callbacks :tick do
                wait_for_notify do |channel, payload|
                  next unless channel == CHANNEL

                  ActiveSupport::Notifications.instrument("notifier_notified.good_job", { payload: payload })
                  parsed_payload = JSON.parse(payload, symbolize_names: true)
                  thr_recipients.each do |recipient|
                    target, method_name = recipient.is_a?(Array) ? recipient : [recipient, :call]
                    target.send(method_name, parsed_payload)
                  end
                end

                reset_connection_errors
              end
            end
          end
        ensure
          Rails.application.executor.wrap do
            run_callbacks :unlisten do
              if thr_enable_listening
                ActiveSupport::Notifications.instrument("notifier_unlisten.good_job") do
                  thr_listening.reset
                  connection.execute("UNLISTEN *")
                end
              end
            end
          end
        end
      end

      @task.add_observer(self, :listen_observer)
      @task.execute
      @task
    end

    def with_connection
      Rails.application.executor.wrap do
        self.connection = Execution.connection_pool.checkout.tap do |conn|
          Execution.connection_pool.remove(conn)
        end
      end
      connection.execute("SET application_name = #{connection.quote(self.class.name)}")

      yield
    ensure
      connection&.disconnect!
      self.connection = nil
    end

    def wait_for_notify
      raw_connection = connection.raw_connection
      if @enable_listening && raw_connection.respond_to?(:wait_for_notify)
        raw_connection.wait_for_notify(WAIT_INTERVAL) do |channel, _pid, payload|
          yield(channel, payload)
        end
      elsif @enable_listening && raw_connection.respond_to?(:jdbc_connection)
        raw_connection.execute_query("SELECT 1")
        notifications = raw_connection.jdbc_connection.getNotifications
        Array(notifications).each do |notification|
          channel = notification.getName
          payload = notification.getParameter
          yield(channel, payload)
        end
        sleep WAIT_INTERVAL
      else
        sleep WAIT_INTERVAL
      end
    end

    def reset_connection_errors
      @connection_errors_count.value = 0
      @connection_errors_reported.make_false
    end

    def synchronize(&block)
      if @mutex.owned?
        yield
      else
        @mutex.synchronize(&block)
      end
    end
  end
end
