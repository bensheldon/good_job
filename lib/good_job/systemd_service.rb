# frozen_string_literal: true

require 'concurrent/timer_task'
require_relative '../../vendor/sd_notify'

module GoodJob
  class SystemdService
    def self.task_observer(time, output, thread_error) # rubocop:disable Lint/UnusedMethodArgument
      return if thread_error.is_a? Concurrent::CancelledOperationError

      GoodJob._on_thread_error(thread_error) if thread_error
    end

    def notifying?
      @watchdog&.running? || false
    end

    def start
      GoodJob::SdNotify.ready
      run_watchdog
    end

    def stop
      @watchdog&.kill
      @watchdog&.wait_for_termination
      GoodJob::SdNotify.stopping
    end

    private

    def run_watchdog
      return false unless GoodJob::SdNotify.watchdog?

      # Systemd recommends pinging the watchdog at half the configured interval:
      # https://www.freedesktop.org/software/systemd/man/sd_watchdog_enabled.html
      interval = watchdog_interval / 2

      GoodJob.logger.info("Pinging systemd watchdog every #{interval.round(1)} seconds")
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
