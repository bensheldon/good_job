# frozen_string_literal: true

require 'concurrent/atomic/event'

module GoodJob # :nodoc:
  #
  # Runs a single {GoodJob::Capsule} inside a subprocess forked by a
  # {GoodJob::Supervisor}. A Subprocess is only used in cluster mode
  # (+GOOD_JOB_SUBPROCESSES+ >= 1). It is instantiated in the child process
  # immediately after +fork+ and is responsible for re-establishing resources
  # that cannot be safely inherited across a fork (database connections,
  # background threads) before booting its Capsule.
  #
  class Subprocess
    # Seconds the subprocess waits between checking whether it should shut down.
    # This also bounds how quickly an orphaned subprocess (whose supervisor has
    # died) notices and exits.
    CHECK_INTERVAL = 5

    # Byte written to the readiness pipe on each heartbeat while the subprocess is ready.
    READY_HEARTBEAT = "1"

    # @param configuration [GoodJob::Configuration] Configuration for this subprocess's Capsule.
    # @param index [Integer] The subprocess's zero-based slot in the cluster, shown in its process title.
    # @param supervisor_pid [Integer] PID of the supervisor process; used to detect orphaning.
    # @param readiness_writer [IO, nil] Write end of the pipe on which the subprocess
    #   heartbeats its readiness to the supervisor; +nil+ disables heartbeating.
    def initialize(configuration:, index: 0, supervisor_pid: ::Process.ppid, readiness_writer: nil)
      @configuration = configuration
      @index = index
      @supervisor_pid = supervisor_pid
      @readiness_writer = readiness_writer
      @stop_subprocess = Concurrent::Event.new
    end

    # Boots the Capsule and blocks until the subprocess is told to shut down (via
    # +SIGTERM+/+SIGINT+), its Capsule shuts itself down, or it is orphaned by a
    # dead supervisor. Intended to be the last thing that runs in a forked child;
    # the process should exit once this method returns.
    # @return [void]
    def run
      $PROGRAM_NAME = "good_job subprocess #{@index}"
      GoodJob.run_lifecycle_hooks(:before_subprocess_boot)

      @capsule = GoodJob::Capsule.new(configuration: @configuration)
      @capsule.start

      install_signal_handlers
      ActiveSupport::Notifications.instrument("subprocess_start.good_job", { pid: ::Process.pid })

      Kernel.loop do
        report_readiness
        @stop_subprocess.wait(CHECK_INTERVAL)
        break if @stop_subprocess.set? || @capsule.shutdown? || orphaned?
      end

      # Emit the shutdown notification *before* draining, so it is recorded even
      # if a slow drain is cut short by a SIGKILL (the supervisor's TERM->KILL
      # escalation on a finite shutdown_timeout, systemd/Kubernetes stop
      # timeouts, or `kill -9`) — nothing can be emitted after a SIGKILL. The
      # wrapping event still records the drain's duration on a clean shutdown.
      ActiveSupport::Notifications.instrument("subprocess_shutdown_start.good_job", { pid: ::Process.pid })
      ActiveSupport::Notifications.instrument("subprocess_shutdown.good_job", { pid: ::Process.pid }) do
        @capsule.shutdown(timeout: @configuration.shutdown_timeout)
      end
    end

    private

    # Heartbeats a readiness byte to the supervisor when this subprocess is ready,
    # so the supervisor can answer the cluster +connected+ health check. Skipped
    # when there is no readiness pipe (e.g. running outside a supervisor).
    # @return [void]
    def report_readiness
      return unless @readiness_writer && ready?

      @readiness_writer.write_nonblock(READY_HEARTBEAT, exception: false)
    rescue IOError
      # The supervisor closed its end (it is shutting down); stop heartbeating.
      @readiness_writer = nil
    end

    # Whether this subprocess is fully ready: its scheduler is running and its
    # notifier is connected. Mirrors the single-process +connected+ health check
    # ({GoodJob::ProbeServer::HealthcheckMiddleware}), evaluated here in the
    # subprocess where those instances live.
    # @return [Boolean]
    def ready?
      schedulers = GoodJob::Scheduler.instances
      notifiers = GoodJob::Notifier.instances
      schedulers.any? && schedulers.all?(&:running?) &&
        notifiers.any? && notifiers.all?(&:connected?)
    end

    # @return [void]
    def install_signal_handlers
      %w[INT TERM].each do |signal|
        trap(signal) { Thread.new { @stop_subprocess.set }.join }
      end
    end

    # @return [Boolean] Whether the supervisor that forked this subprocess is gone.
    def orphaned?
      ::Process.ppid != @supervisor_pid
    end
  end
end
