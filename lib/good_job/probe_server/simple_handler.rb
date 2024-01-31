# frozen_string_literal: true

module GoodJob
  class ProbeServer
    class SimpleHandler
      SOCKET_READ_TIMEOUT = 5 # in seconds

      def initialize(app, options = {})
        @app    = app
        @port   = options[:port]
        @logger = options[:logger]

        @running = Concurrent::AtomicBoolean.new(false)
      end

      def stop
        @running.make_false
        @server&.close
      end

      def running?
        @running.true?
      end

      def build_future
        Concurrent::Future.new { run }
      end

      private

      def run
        @running.make_true
        start_server
        handle_connections if @running.true?
      rescue StandardError => e
        @logger.error "Server encountered an error: #{e}"
      ensure
        stop
      end

      def start_server
        @server = TCPServer.new('0.0.0.0', @port)
      rescue StandardError => e
        @logger.error "Failed to start server: #{e}"
        @running.make_false
      end

      def handle_connections
        while @running.true?
          begin
            ready_sockets, = IO.select([@server], nil, nil, SOCKET_READ_TIMEOUT)
            next unless ready_sockets

            client = @server.accept_nonblock
            request = client.gets

            if request
              status, headers, body = @app.call(parse_request(request))
              respond(client, status, headers, body)
            end

            client.close
          rescue IO::WaitReadable, Errno::EINTR, Errno::EPIPE
            retry
          end
        end
      end

      def parse_request(request)
        method, full_path = request.split
        path, query = full_path.split('?')
        { 'REQUEST_METHOD' => method, 'PATH_INFO' => path, 'QUERY_STRING' => query || '' }
      end

      def respond(client, status, headers, body)
        client.write "HTTP/1.1 #{status}\r\n"
        headers.each { |key, value| client.write "#{key}: #{value}\r\n" }
        client.write "\r\n"
        body.each { |part| client.write part.to_s }
      end
    end
  end
end
