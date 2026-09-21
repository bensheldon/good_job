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
      case handler
      when :webrick
        begin
          require 'webrick'
          WebrickHandler.new(app, port: port, logger: GoodJob.logger)
        rescue LoadError
          GoodJob.deprecator.warn(<<~MSG)
            `probe_handler: :webrick` is specified but WEBrick is not in the load path, so GoodJob's own webserver is used instead.
            Add `gem "webrick"` to your Gemfile. This fallback is deprecated and will raise in the next release.
          MSG
          SimpleHandler.new(app, port: port, logger: GoodJob.logger)
        end
      when nil
        SimpleHandler.new(app, port: port, logger: GoodJob.logger)
      else
        GoodJob.deprecator.warn(<<~MSG)
          `probe_handler: #{handler.inspect}` is not supported, so GoodJob's own webserver is used instead.
          Specify `:webrick` or `nil`. This fallback is deprecated and will raise in the next release.
        MSG
        SimpleHandler.new(app, port: port, logger: GoodJob.logger)
      end
    end
  end
end
