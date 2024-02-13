# frozen_string_literal: true

module GoodJob
  class ProbeServer
    class HealthcheckMiddleware
      def initialize(app)
        @app = app
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
          @app.call(env)
        end
      end
    end
  end
end
