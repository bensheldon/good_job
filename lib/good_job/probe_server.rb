# frozen_string_literal: true

module GoodJob
  class ProbeServer
    def self.task_observer(time, output, thread_error) # rubocop:disable Lint/UnusedMethodArgument
      return if thread_error.is_a? Concurrent::CancelledOperationError

      GoodJob._on_thread_error(thread_error) if thread_error
    end

    def initialize(port:)
      @port = port
    end

    def start
      @handler = HttpServer.new(self, port: @port, logger: GoodJob.logger)
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

    def call(env)
      case Rack::Request.new(env).path
      when '/', '/status'
        [200, {}, ["OK"]]
      when '/status/started'
        started = GoodJob::Scheduler.instances.any? && GoodJob::Scheduler.instances.all?(&:running?)
        started ? [200, {}, ["Started"]] : [503, {}, ["Not started"]]
      when '/status/connected'
        connected = GoodJob::Scheduler.instances.any? && GoodJob::Scheduler.instances.all?(&:running?) &&
                    GoodJob::Notifier.instances.any? && GoodJob::Notifier.instances.all?(&:connected?)
        connected ? [200, {}, ["Connected"]] : [503, {}, ["Not connected"]]
      else
        [404, {}, ["Not found"]]
      end
    end
  end
end
