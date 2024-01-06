# frozen_string_literal: true

module GoodJob
  class ProbeServer
    def self.task_observer(time, output, thread_error) # rubocop:disable Lint/UnusedMethodArgument
      return if thread_error.is_a? Concurrent::CancelledOperationError

      GoodJob._on_thread_error(thread_error) if thread_error
    end

    def self.default_app
      ::Rack::Builder.new do
        use GoodJob::ProbeServer::HealthcheckMiddleware
        run GoodJob::ProbeServer::NotFoundApp
      end
    end

    def initialize(port:, handler: nil, app: nil)
      app ||= self.class.default_app
      @handler = build_handler(port: port, handler: handler, app: app)
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

    def build_handler(port:, handler:, app:)
      if handler == :webrick
        begin
          require 'webrick'
          WebrickHandler.new(app, port: port, logger: GoodJob.logger)
        rescue LoadError
          GoodJob.logger.warn("WEBrick was requested as the probe server handler, but it's not in the load path. GoodJob doesn't keep WEBrick as a dependency, so you'll have to make sure its added to your Gemfile to make use of it. GoodJob will fallback to its own webserver in the meantime.")
          SimpleHandler.new(app, port: port, logger: GoodJob.logger)
        end
      else
        SimpleHandler.new(app, port: port, logger: GoodJob.logger)
      end
    end
  end
end
