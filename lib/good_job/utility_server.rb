# frozen_string_literal: true

module GoodJob
  class UtilityServer
    def self.task_observer(time, output, thread_error) # rubocop:disable Lint/UnusedMethodArgument
      return if thread_error.is_a? Concurrent::CancelledOperationError

      GoodJob._on_thread_error(thread_error) if thread_error
    end

    def initialize(app:, port:)
      @port = port
      @app = app
    end

    def start
      @handler = HttpServer.new(@app, port: @port, logger: GoodJob.logger)
      @future = Concurrent::Future.new { @handler.run }
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
  end
end
