# frozen_string_literal: true

module GoodJob
  class ProbeServer
    # Rack middleware that answers health checks for a {GoodJob::Supervisor} in
    # cluster mode. Unlike {HealthcheckMiddleware}, which inspects the current
    # process's schedulers and notifiers, this reports on the cluster as a whole:
    # the supervisor process runs no scheduler, so +started+ is derived from
    # whether all configured subprocesses are currently running, and +connected+
    # from whether each subprocess has recently reported itself ready (its
    # scheduler running and notifier connected) over its readiness heartbeat.
    class ClusterHealthcheckMiddleware
      def initialize(app, supervisor)
        @app = app
        @supervisor = supervisor
      end

      def call(env)
        case Rack::Request.new(env).path
        when '/', '/status'
          [200, {}, ["OK"]]
        when '/status/started'
          @supervisor.started? ? [200, {}, ["Started"]] : [503, {}, ["Not started"]]
        when '/status/connected'
          @supervisor.connected? ? [200, {}, ["Connected"]] : [503, {}, ["Not connected"]]
        else
          @app.call(env)
        end
      end
    end
  end
end
