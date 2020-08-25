require 'concurrent/atomic/atomic_boolean'

module GoodJob # :nodoc:
  #
  # Wrapper for Postgres LISTEN/NOTIFY
  #
  class Notifier
    CHANNEL = 'good_job'.freeze
    POOL_OPTIONS = {
      min_threads: 0,
      max_threads: 1,
      auto_terminate: true,
      idletime: 60,
      max_queue: 1,
      fallback_policy: :discard,
    }.freeze
    WAIT_INTERVAL = 1

    # @!attribute [r] instances
    #   @!scope class
    #   @return [array<GoodJob:Adapter>] the instances of +GoodJob::Notifier+
    cattr_reader :instances, default: [], instance_reader: false

    def self.notify(message)
      connection = ActiveRecord::Base.connection
      connection.exec_query <<~SQL
        NOTIFY #{CHANNEL}, #{connection.quote(message.to_json)}
      SQL
    end

    attr_reader :recipients

    def initialize(*recipients)
      @recipients = Concurrent::Array.new(recipients)
      @listening = Concurrent::AtomicBoolean.new(false)

      self.class.instances << self

      create_pool
      listen
    end

    def listening?
      @listening.true?
    end

    def restart(wait: true)
      shutdown(wait: wait)
      create_pool
      listen
    end

    def shutdown(wait: true)
      return unless @pool.running?

      @pool.shutdown
      @pool.wait_for_termination if wait
    end

    def shutdown?
      !@pool.running?
    end

    private

    def create_pool
      @pool = Concurrent::ThreadPoolExecutor.new(POOL_OPTIONS)
    end

    def listen
      future = Concurrent::Future.new(args: [@recipients, @pool, @listening], executor: @pool) do |recipients, pool, listening|
        begin
          Rails.application.reloader.wrap do
            with_listen_connection do |conn|
              ActiveSupport::Notifications.instrument("notifier_listen.good_job") do
                conn.async_exec "LISTEN #{CHANNEL}"
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
            end
          end
        rescue StandardError => e
          ActiveSupport::Notifications.instrument("notifier_notify_error.good_job", { error: e })
          raise
        ensure
          @listening.make_false
          ActiveSupport::Notifications.instrument("notifier_unlisten.good_job") do
            conn.async_exec "UNLISTEN *"
          end
        end
      end

      future.add_observer(self, :listen_observer)
      future.execute
    end

    def listen_observer(_time, _result, _thread_error)
      listen unless shutdown?
    end

    def with_listen_connection
      ar_conn = ActiveRecord::Base.connection_pool.checkout.tap do |conn|
        ActiveRecord::Base.connection_pool.remove(conn)
      end
      pg_conn = ar_conn.raw_connection
      pg_conn.exec("SET application_name = #{pg_conn.escape_identifier(self.class.name)}")
      yield pg_conn
    ensure
      ar_conn.disconnect!
    end
  end
end
