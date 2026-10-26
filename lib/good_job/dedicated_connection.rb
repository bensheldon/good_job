# frozen_string_literal: true

require "concurrent/atomic/atomic_boolean"
require "concurrent/atomic/atomic_fixnum"
require "concurrent/atomic/event"
require "good_job/reactor"

module GoodJob # :nodoc:
  #
  # A database connection held outside the connection pool, managed on a {GoodJob::Reactor}'s thread.
  # The connection is kept alive, and is replaced after connection errors and, optionally, on a schedule.
  #
  # Components (e.g. {GoodJob::Notifier} and {GoodJob::ProcessHeartbeat}) attach to the connection with
  # {#on_connect}, {#on_disconnect}, {#every}, and {#after_task}. Each must attach before {#start}. Hooks run on the
  # reactor thread in the order they were attached.
  #
  class DedicatedConnection
    # Seconds between checks of the connection
    TICK_INTERVAL = 1
    # Seconds to wait if database cannot be connected to
    RECONNECT_INTERVAL = 5
    # Number of consecutive connection errors before reporting an error
    CONNECTION_ERRORS_REPORTING_THRESHOLD = 6
    # Interval for emitting a noop SQL query to keep the connection alive
    KEEPALIVE_INTERVAL = 10
    # Seconds after which to replace the connection, when replacing it on a schedule. Long-lived connections
    # are more likely to be dropped by the network. Each connection's age is jittered by up to 10%.
    RETIREMENT_AGE = 600

    # Connection errors that will wait {RECONNECT_INTERVAL} before reconnecting
    CONNECTION_ERRORS = %w[
      ActiveRecord::ConnectionNotEstablished
      ActiveRecord::StatementInvalid
      PG::UnableToSend
      PG::Error
    ].freeze

    include InstanceRegistry

    # @return [GoodJob::Reactor]
    attr_reader :reactor

    # @param reactor [GoodJob::Reactor]
    # @param name [String] Postgres application_name of the connection.
    # @param retirement_age [Numeric, nil] Seconds after which the connection is replaced; nil never replaces it.
    def initialize(reactor: GoodJob::Reactor.new(name: "good_job-reactor"), name: "GoodJob", retirement_age: nil)
      @reactor = reactor
      @name = name
      @monitor = Monitor.new
      @started = false
      @connected = Concurrent::Event.new
      @connection_errors_count = Concurrent::AtomicFixnum.new(0)
      @connection_errors_reported = Concurrent::AtomicBoolean.new(false)
      @last_keepalive_time = Time.current

      @reactor.loop.on_error { |error| report_error(error) }
      @reactor.on_failure { |error| report_error(error) }

      retirement_age &&= retirement_age * (0.9 + (0.2 * Kernel.rand))
      @resource = @reactor.create_resource(name: :connection, retirement_age: retirement_age, on_fault: method(:connection_fault))
      @resource.around_add { |add, generation| add_connection(add, generation) }
      @resource.around_remove { |remove, generation| remove_connection(remove, generation) }
      @resource.around_task { |task, generation| connection_task(task, generation) }
      every(TICK_INTERVAL) { reset_connection_errors }
      every(KEEPALIVE_INTERVAL, jitter: 0.1) { |generation| keepalive(generation) }
    end

    # Calls the block with each new connection's generation, before it becomes current. An error faults the connection.
    # @yieldparam generation [GoodJob::Reactor::Resource::Generation] Its +value+ is the connection.
    # @yieldparam replacing [Boolean] Whether it replaces a connection that is still connected.
    # @return [void]
    def on_connect
      @resource.around_promotion do |promotion, previous_generation, next_generation|
        if next_generation
          begin
            Rails.application.executor.wrap { yield next_generation, previous_generation&.alive? || false }
          rescue StandardError => e
            # A faulted connection is replaced; failing the promotion would stop the reactor.
            next_generation.fault(e)
          end
        end
        promotion.call
      end
    end

    # Calls the block with each connection's generation before it is disconnected.
    # @yieldparam generation [GoodJob::Reactor::Resource::Generation]
    # @yieldparam replaced [Boolean] Whether another connection has already replaced it.
    # @return [void]
    def on_disconnect
      @resource.around_remove do |remove, generation|
        Rails.application.executor.wrap { yield generation, replaced?(generation) } if generation.value
      ensure
        remove.call
      end
    end

    # Calls the block with the current connection's generation every +seconds+.
    # @yieldparam generation [GoodJob::Reactor::Resource::Generation]
    # @return [void]
    def every(seconds, jitter: 0)
      @resource.every(seconds, jitter: jitter) { |resource| yield resource.current_generation }
    end

    # Calls the block after each task that runs on the connection (from {#every}, {#post}, or a
    # generation's watchers and timers), unless the task faulted the connection.
    # @yieldparam generation [GoodJob::Reactor::Resource::Generation]
    # @return [void]
    def after_task
      @resource.around_task do |task, generation|
        task.call
        yield generation if generation.alive?
      end
    end

    # Starts the reactor, which connects in the background.
    # @return [void]
    def start
      synchronize do
        return if @started && @reactor.started?

        register_instance
        @started = true
        @reactor.start(wait: false)
      end
    end

    def running?
      @reactor.started?
    end

    def shutdown?
      @reactor.stopped? && !@reactor.loop.alive?
    end

    # Shut down the reactor and disconnect.
    # @param timeout [Numeric, nil] Seconds to wait; shares same values as {GoodJob::Reactor#stop}.
    # @return [Boolean, nil]
    def shutdown(timeout: -1)
      synchronize do
        if @started
          @started = false
          @reactor.stop(timeout: timeout)
        else
          @reactor.wait_for_stop(timeout: timeout)
        end
        @connected.reset if shutdown?
        shutdown?
      end
    end

    # Tests whether a connection has been established.
    # @param timeout [Numeric, nil] Seconds to wait for condition to be true, -1 is forever
    # @return [true, false, nil]
    def connected?(timeout: nil)
      if timeout.nil?
        @connected.set?
      else
        @connected.wait(timeout&.negative? ? nil : timeout)
      end
    end

    # Runs the block on the reactor thread with the current connection.
    # @return [GoodJob::Reactor::Result]
    def post
      @resource.post { |resource| yield resource.value }
    end

    private

    delegate :synchronize, to: :@monitor

    def add_connection(add, generation)
      Rails.application.executor.wrap do
        generation.value = ::GoodJob::Job.connection_pool.checkout.tap do |conn|
          ::GoodJob::Job.connection_pool.remove(conn)
        end
      end
      generation.value.execute("SET application_name = #{generation.value.quote(@name)}")
      @connected.set
      add.call
    end

    # Attached first, so it is outermost: disconnects after every other hook.
    def remove_connection(remove, generation)
      remove.call
    ensure
      generation.value&.disconnect!
    end

    # Connection errors fault the connection, which is replaced after {RECONNECT_INTERVAL}.
    def connection_task(task, generation)
      Rails.application.executor.wrap { task.call }
    rescue *connection_error_classes => e
      generation.fault(e)
    end

    def keepalive(generation)
      raw_connection = generation.value.raw_connection
      if raw_connection.respond_to?(:async_exec)
        raw_connection.async_exec("SELECT 1")
      else
        raw_connection.execute_query("SELECT 1")
      end
      @last_keepalive_time = Time.current
    end

    # Called by the reactor after each fault.
    # @return [Numeric] Seconds to wait before reconnecting
    def connection_fault(generation, _faults)
      error = generation.fault_error
      ActiveSupport::Notifications.instrument("notifier_notify_error.good_job", { error: error })

      if connection_error_classes.any? { |error_class| error.is_a?(error_class) }
        @connection_errors_count.increment
        if @connection_errors_reported.false? && @connection_errors_count.value >= CONNECTION_ERRORS_REPORTING_THRESHOLD
          @connected.reset
          GoodJob._on_thread_error(error)
          @connection_errors_reported.make_true
        end
      else
        GoodJob._on_thread_error(error)
      end

      RECONNECT_INTERVAL
    end

    # Whether another connection is current, so this one is being replaced.
    def replaced?(generation)
      current = @resource.current_generation
      !current.nil? && !current.equal?(generation) && current.alive?
    end

    def connection_error_classes
      @_connection_error_classes ||= CONNECTION_ERRORS.filter_map(&:safe_constantize)
    end

    def report_error(error)
      ActiveSupport::Notifications.instrument("notifier_notify_error.good_job", { error: error })
      GoodJob._on_thread_error(error)
    end

    def reset_connection_errors
      @connection_errors_count.value = 0
      @connection_errors_reported.make_false
    end
  end
end
