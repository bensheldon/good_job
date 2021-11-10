# frozen_string_literal: true

module GoodJob
  class ProbeServer
    RACK_SERVER = 'webrick'

    def self.task_observer(time, output, thread_error) # rubocop:disable Lint/UnusedMethodArgument
      return if thread_error.is_a? Concurrent::CancelledOperationError

      GoodJob.on_thread_error.call(thread_error) if thread_error && GoodJob.on_thread_error.respond_to?(:call)
    end

    def initialize(port:)
      @port = port
    end

    def start
      @handler = Rack::Handler.get(RACK_SERVER)
      @future = Concurrent::Future.new(args: [@handler, @port, GoodJob.logger]) do |thr_handler, thr_port, thr_logger|
        thr_handler.run(self, Port: thr_port, Logger: thr_logger, AccessLog: [])
      end
      @future.add_observer(self.class, :task_observer)
      @future.execute
    end

    def running?
      @handler&.instance_variable_get(:@server)&.status == :Running
    end

    def stop
      @handler&.shutdown
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
                    GoodJob::Notifier.instances.any? && GoodJob::Notifier.instances.all?(&:listening?)
        connected ? [200, {}, ["Connected"]] : [503, {}, ["Not connected"]]
      else
        [404, {}, ["Not found"]]
      end
    end
  end
end
