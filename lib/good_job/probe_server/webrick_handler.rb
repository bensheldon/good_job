# frozen_string_literal: true

module GoodJob
  class ProbeServer
    class WebrickHandler
      def initialize(app, options = {})
        @app    = app
        @port   = options[:port]
        @logger = options[:logger]
        @handler = ::Rack::Handler.get('webrick')
      end

      def stop
        @handler&.shutdown
      end

      def running?
        @handler&.instance_variable_get(:@server)&.status == :Running
      end

      def build_future
        Concurrent::Future.new(args: [@handler, @port, GoodJob.logger]) do |thr_handler, thr_port, thr_logger|
          thr_handler.run(@app, Port: thr_port, Host: '0.0.0.0', Logger: thr_logger, AccessLog: [])
        end
      end
    end
  end
end
