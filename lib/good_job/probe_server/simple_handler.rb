# typed: true
# frozen_string_literal: true

require "concurrent/atomic/atomic_boolean"
require "concurrent/future"

module GoodJob
  class ProbeServer
    class SimpleHandler
      SOCKET_READ_TIMEOUT = 5 # in seconds
      CLIENT_READ_TIMEOUT = 1 # in seconds
      MAX_REQUEST_LINE_LENGTH = 8192 # in bytes

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

      # Closes this process's copy of the socket, for a process that inherited it across a fork.
      def close_socket
        @server&.close
      end

      def running?
        @running.true?
      end

      # Binds the listening socket, before the thread that serves it is started, so
      # that a process forking afterwards can reliably close its inherited copy.
      def listen
        @server = TCPServer.new('0.0.0.0', @port)
        @running.make_true
      rescue StandardError => e
        @logger.error "Failed to start server: #{e}"
      end

      def build_future
        Concurrent::Future.new { run }
      end

      private

      def run
        handle_connections if @running.true?
      rescue StandardError => e
        @logger.error "Server encountered an error: #{e.class} - #{e}"
      ensure
        stop
      end

      def handle_connections
        while @running.true?
          begin
            ready_sockets, = IO.select([@server], nil, nil, SOCKET_READ_TIMEOUT)
            next unless ready_sockets

            client = @server.accept_nonblock
            handle_client(client)
          rescue IO::WaitReadable, Errno::EINTR
            retry # on transient errors
          rescue Errno::EBADF
            break if @server&.closed? # Server shut down - stop

            raise
          end
        end
      end

      def handle_client(client)
        request_line = read_request_line(client)
        return unless request_line

        env = parse_request(request_line)
        if env
          status, headers, body = @app.call(env)
          respond(client, status, headers, body)
        else
          respond(client, 400, { "Content-Type" => "text/plain" }, ["Bad Request"])
        end
      rescue Errno::EPIPE, Errno::ECONNRESET
        nil # Client disconnected - continue
      rescue StandardError => e
        @logger.error "Server failed to handle request: #{e.class} - #{e}"
      ensure
        client.close
      end

      # Reads the request line without blocking longer than CLIENT_READ_TIMEOUT,
      # so that an idle or slow client can't stall the server.
      def read_request_line(client)
        deadline = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + CLIENT_READ_TIMEOUT
        buffer = +""
        until buffer.include?("\n")
          return if buffer.bytesize > MAX_REQUEST_LINE_LENGTH

          chunk = client.read_nonblock(1024, exception: false)
          case chunk
          when :wait_readable
            remaining = deadline - ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
            return if remaining <= 0 || IO.select([client], nil, nil, remaining).nil?
          when nil
            break # EOF
          else
            buffer << chunk
          end
        end
        buffer.lines.first
      end

      def parse_request(request)
        method, full_path = request.split
        return if method.nil? || full_path.nil?

        path, query = full_path.split('?', 2)
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
