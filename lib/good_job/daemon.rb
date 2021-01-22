module GoodJob
  #
  # Manages daemonization of the current process.
  #
  class Daemon
    # The path of the generated pidfile.
    # @return [Pathname,String]
    attr_reader :pidfile

    # @param pidfile [Pathname,String] Pidfile path
    def initialize(pidfile:)
      @pidfile = pidfile
    end

    # Daemonizes the current process and writes out a pidfile.
    def daemonize
      check_pid
      Process.daemon
      write_pid
    end

    private

    def write_pid
      File.open(pidfile, ::File::CREAT | ::File::EXCL | ::File::WRONLY) { |f| f.write(Process.pid.to_s) }
      at_exit { File.delete(pidfile) if File.exist?(pidfile) }
    rescue Errno::EEXIST
      check_pid
      retry
    end

    def delete_pid
      File.delete(pidfile) if File.exist?(pidfile)
    end

    def check_pid
      case pid_status(pidfile)
      when :running, :not_owned
        abort "A server is already running. Check #{pidfile}"
      when :dead
        File.delete(pidfile)
      end
    end

    def pid_status(pidfile)
      return :exited unless File.exist?(pidfile)

      pid = ::File.read(pidfile).to_i
      return :dead if pid.zero?

      Process.kill(0, pid) # check process status
      :running
    rescue Errno::ESRCH
      :dead
    rescue Errno::EPERM
      :not_owned
    end
  end
end
