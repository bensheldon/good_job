# frozen_string_literal: true

require 'concurrent/timer_task'
require 'good_job/sd_notify'

module GoodJob # :nodoc:
  #
  # Manages communication with systemd to notify it about the status of the
  # GoodJob CLI. If it doesn't look like systemd is controlling the process,
  # SystemdService doesn't do anything.
  #
  class SystemdService
    def self.task_observer(_time, _output, thread_error) # :nodoc:
      return if !thread_error || thread_error.is_a?(Concurrent::CancelledOperationError)

      ActiveSupport::Notifications.instrument("systemd_watchdog_error.good_job", { error: thread_error })
      GoodJob._on_thread_error(thread_error)
    end

    # Indicates whether the service is actively notifying systemd's watchdog.
    def notifying?
      @watchdog&.running? || false
    end

    # Notify systemd that the process is ready. If the service is configured in
    # systemd to use the watchdog, this will also start pinging the watchdog.
    def start
      GoodJob::SdNotify.ready
      run_watchdog
    end

    # Notify systemd that the process is stopping and stop pinging the watchdog
    # if currently doing so. If given a block, it will wait for the block to
    # complete before stopping watchdog notifications, so systemd has a clear
    # indication when graceful shutdown started and finished.
    def stop
      GoodJob::SdNotify.stopping

      yield if block_given?

      @watchdog&.kill
      @watchdog&.wait_for_termination
    end

    private

    def run_watchdog
      return false unless GoodJob::SdNotify.watchdog?

      # Systemd recommends pinging the watchdog at half the configured interval:
      # https://www.freedesktop.org/software/systemd/man/sd_watchdog_enabled.html
      interval = watchdog_interval / 2

      ActiveSupport::Notifications.instrument("systemd_watchdog_start.good_job", { interval: interval })
      @watchdog = Concurrent::TimerTask.execute(execution_interval: interval) do
        GoodJob::SdNotify.watchdog
      end
      @watchdog.add_observer(self.class, :task_observer)

      true
    end

    def watchdog_interval
      return 0.0 unless GoodJob::SdNotify.watchdog?

      Integer(ENV.fetch('WATCHDOG_USEC')) / 1_000_000.0
    end
  end
end
