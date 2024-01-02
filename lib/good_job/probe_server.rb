# frozen_string_literal: true

module GoodJob
  class ProbeServer
    def self.task_observer(time, output, thread_error) # rubocop:disable Lint/UnusedMethodArgument
      return if thread_error.is_a? Concurrent::CancelledOperationError

      GoodJob._on_thread_error(thread_error) if thread_error
    end

    def initialize(port:, handler: nil, app: default_probe_server)
      @port = port
      @app = app
      @handler = handler || default_handler
    end

    def start
      @future = @handler.build_future
      @future.add_observer(self.class, :task_observer)
      @future.execute
    end

    def running?
      @handler&.running?
    end

    def stop
      @handler&.stop
      @future&.value # wait for Future to exit
    end

    private

    def default_probe_server
      Rack::Builder.new do
        use Middleware::Healthcheck
        run Middleware::Catchall.new
      end
    end

    def default_handler
      HttpServer.new(@app, port: @port, logger: GoodJob.logger)
    end
  end
end
