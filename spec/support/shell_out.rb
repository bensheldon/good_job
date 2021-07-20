# frozen_string_literal: true
require 'open3'

class ShellOut
  WaitTimeout = Class.new(StandardError)
  PROCESS_EXIT = "[PROCESS EXIT]"

  def self.command(command, env: {}, &block)
    new.command(command, env: env, &block)
  end

  attr_reader :output

  def initialize
    @output = Concurrent::Array.new
  end

  def command(command, env: {})
    all_env = ENV.to_h.merge(env)
    Open3.popen3(all_env, command, chdir: Rails.root) do |stdin, stdout, stderr, wait_thr|
      pid = wait_thr.pid
      stdin.close

      stdout_future = Concurrent::Promises.future(stdout, @output) do |fstdout, foutput|
        loop do
          line = fstdout.gets
          break unless line

          foutput << line
        end
      end
      stderr_future = Concurrent::Promises.future(stderr, @output) do |fstderr, foutput|
        loop do
          line = fstderr.gets
          break unless line

          foutput << line
        end
      end

      begin
        yield(self)
      ensure
        begin
          Process.kill('TERM', pid)
          wait_thr.value
        rescue Errno::ESRCH
          @output << PROCESS_EXIT
        end
      end

      stdout_future.value
      stderr_future.value

      @output
    end
  end
end
