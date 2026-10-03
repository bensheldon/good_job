# frozen_string_literal: true

require 'concurrent/atomic/atomic_reference'
require 'concurrent/hash'

module GoodJob # :nodoc:
  #
  # A Supervisor runs GoodJob in "cluster mode": instead of executing jobs in
  # the current process, it forks and supervises +GOOD_JOB_SUBPROCESSES+ child
  # processes, each of which runs its own {GoodJob::Capsule} via
  # {GoodJob::Subprocess}. Forking lets the operating system share loaded
  # Rails/application memory pages copy-on-write across the subprocesses.
  #
  # The Supervisor itself runs no Capsule, Scheduler, or Notifier — it only
  # forks, monitors, and (when a subprocess dies unexpectedly) replaces its
  # children, and coordinates graceful shutdown. Forking is only ever performed
  # from the main thread (inside {#start}) to avoid a forked child inheriting a
  # mutex left locked by another thread.
  #
  class Supervisor
    # Seconds the supervise loop sleeps between polling for exited subprocesses.
    # +SIGCHLD+ interrupts this sleep so replacement is prompt; the interval is
    # only a backstop.
    SUPERVISE_INTERVAL = 5

    # Seconds between polls while waiting for subprocesses to exit during a
    # bounded (timeout) shutdown.
    REAP_INTERVAL = 0.1

    # Extra seconds the supervisor waits after +SIGTERM+ — on top of a
    # subprocess's own drain budget (its +shutdown_timeout+) — before escalating
    # to +SIGKILL+, so a subprocess still draining within its budget is not
    # killed prematurely.
    SHUTDOWN_GRACE = 5

    # Signals that trigger a graceful shutdown (drain jobs, then exit).
    GRACEFUL_SIGNALS = %w[INT TERM].freeze
    # Signals that trigger an immediate shutdown (interrupt running jobs).
    IMMEDIATE_SIGNALS = %w[QUIT].freeze

    # A subprocess that exits sooner than this many seconds after being forked
    # is treated as a failed boot; its replacement is delayed with backoff.
    MIN_HEALTHY_UPTIME = 10

    # Bounds (seconds) for the exponential backoff between replacements of a
    # repeatedly crash-looping subprocess.
    MIN_BACKOFF_DELAY = 1
    MAX_BACKOFF_DELAY = 30

    # Seconds after a subprocess's last readiness heartbeat before it is treated
    # as disconnected by the +connected+ health check. Comfortably larger than a
    # subprocess's heartbeat interval so an occasional missed beat doesn't flap.
    CONNECTED_TIMEOUT = 15

    # Monotonic time in seconds, used for internal timeouts so a wall-clock
    # change can't skew them.
    # @return [Float]
    def self.monotonic
      ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    end

    # The supervisor's record of a single forked subprocess: enough to monitor
    # its lifetime and re-fork a replacement from the same recipe (with backoff
    # when it is crash-looping). +index+ is the subprocess's stable zero-based
    # slot, carried to a replacement so it keeps the same identity; +recipe+ is
    # the {GoodJob::Configuration} the subprocess runs; +restart_count+ is the
    # number of consecutive fast exits that led to this subprocess being forked;
    # +readiness_reader+ is the read end of the pipe the subprocess heartbeats its
    # readiness on.
    class SubprocessHandle
      attr_reader :pid, :index, :recipe, :restart_count, :readiness_reader

      def initialize(pid:, recipe:, index: 0, restart_count: 0, readiness_reader: nil)
        @pid = pid
        @index = index
        @recipe = recipe
        @restart_count = restart_count
        @readiness_reader = readiness_reader
        @started_at = Supervisor.monotonic
        # Written by the supervise loop, read by the probe server thread.
        @last_ready_at = Concurrent::AtomicReference.new(nil)
      end

      # Seconds since this subprocess was forked (monotonic, immune to wall-clock changes).
      # @return [Float]
      def uptime
        Supervisor.monotonic - @started_at
      end

      # Records that the subprocess reported itself ready at the given monotonic time.
      # @param at [Float]
      # @return [void]
      def mark_ready(at)
        @last_ready_at.set(at)
      end

      # Whether the subprocess has reported itself ready recently enough to be
      # considered connected. A subprocess that stops heartbeating (hung, or lost
      # its notifier connection) goes stale and is no longer connected.
      # @param now [Float] the current monotonic time
      # @param timeout [Numeric] seconds after which a readiness report is stale
      # @return [Boolean]
      def connected?(now, timeout)
        last_ready_at = @last_ready_at.get
        !last_ready_at.nil? && (now - last_ready_at) <= timeout
      end
    end

    # @param configuration [GoodJob::Configuration] Configuration shared by every subprocess.
    def initialize(configuration = GoodJob.configuration)
      @configuration = configuration
      # pid => SubprocessHandle. Mutated only from the main thread, but read from
      # the probe server thread (via #started?), so it must be thread-safe.
      @subprocesses = Concurrent::Hash.new
      @received_signals = []
      @self_pipe_reader, @self_pipe_writer = IO.pipe
      @stopped = false
      @shutdown_timeout = nil
    end

    # Forks the configured number of subprocesses and blocks, supervising them,
    # until a shutdown signal (+SIGINT+/+SIGTERM+ for graceful, +SIGQUIT+ for
    # immediate) is received. When it returns, all subprocesses have exited.
    # @param on_shutdown [#call, nil] Called once, after a shutdown signal is
    #   received and immediately before the subprocesses are told to drain, so a
    #   caller can act on the start of the shutdown rather than only its
    #   completion. An error raised by it is reported and does not prevent the
    #   shutdown.
    # @return [void]
    def start(on_shutdown: nil)
      @supervisor_pid = ::Process.pid
      $PROGRAM_NAME = "good_job supervisor [#{@configuration.subprocesses} subprocesses]"
      install_signal_handlers

      ActiveSupport::Notifications.instrument("cluster_start.good_job", { subprocesses: @configuration.subprocesses })
      @configuration.subprocess_configs.each_with_index { |config, index| spawn_subprocess(config, index: index) }
      # Bind the probe port only after the initial subprocesses are forked so they
      # don't inherit the listening socket. Replacements forked later do inherit it,
      # and close it immediately (see {#spawn_subprocess}).
      start_probe_server

      supervise(on_shutdown: on_shutdown)
    ensure
      stop_probe_server
      reset_signal_handlers
      # By now every subprocess has been reaped (and its reader closed); close any
      # that remain defensively so no descriptor leaks. Iterate a snapshot of the
      # keys since forget_subprocess mutates the hash.
      remaining_pids = @subprocesses.keys
      remaining_pids.each { |pid| forget_subprocess(pid) }
      @self_pipe_reader.close unless @self_pipe_reader.closed?
      @self_pipe_writer.close unless @self_pipe_writer.closed?
    end

    # @return [Boolean] Whether the supervisor is currently supervising subprocesses.
    def running?
      !@stopped && @supervisor_pid == ::Process.pid
    end

    # Whether the cluster is ready: the supervisor is running and every
    # configured subprocess is currently alive. Used by the cluster health check.
    # @return [Boolean]
    def started?
      running? && @subprocesses.size >= @configuration.subprocesses
    end

    # Whether the cluster is connected: it is {#started?} and every subprocess has
    # recently reported itself ready (its scheduler running and notifier
    # connected). This mirrors the single-process +connected+ health check, but
    # aggregated across subprocesses via their readiness heartbeats. Read from the
    # probe server thread. Used by the cluster health check.
    # @return [Boolean]
    def connected?
      return false unless started?

      now = Supervisor.monotonic
      subprocesses = @subprocesses.values
      !subprocesses.empty? && subprocesses.all? { |handle| handle.connected?(now, CONNECTED_TIMEOUT) }
    end

    private

    # The main supervise loop. Runs on the calling (main) thread so that all
    # forking happens on the main thread.
    # @param on_shutdown [#call, nil] See {#start}.
    # @return [void]
    def supervise(on_shutdown: nil)
      until @stopped
        process_signals
        break if @stopped

        reap_and_replace
        wait_for_wakeup
      end

      begin
        on_shutdown&.call
      rescue StandardError => e
        GoodJob._on_thread_error(e)
      end

      terminate_subprocesses(@shutdown_timeout.nil? ? @configuration.shutdown_timeout : @shutdown_timeout)
      ActiveSupport::Notifications.instrument("cluster_shutdown.good_job", { pid: @supervisor_pid })
    end

    # Forks a single subprocess running the given recipe (its {GoodJob::Configuration})
    # and records a {SubprocessHandle} for it. Must only be called from the main thread.
    #
    # The +before_supervisor_fork+ lifecycle hooks run immediately before *every*
    # fork — not just the initial batch — so the invariant they exist to maintain
    # (the supervisor holds no fork-unsafe resource, e.g. a live database
    # connection, at the instant of a fork) also holds for replacement forks.
    #
    # Each subprocess gets a private pipe: the child writes readiness heartbeats to
    # the write end (see {GoodJob::Subprocess}) and the supervisor reads them from
    # the {SubprocessHandle}'s read end to answer the cluster +connected+ health check.
    # @param recipe [GoodJob::Configuration]
    # @param index [Integer] The subprocess's stable zero-based slot, used in its
    #   process title; a replacement is forked with the same index.
    # @param restart_count [Integer] Consecutive fast-exit count carried to the new subprocess.
    # @return [Integer] The forked process's PID.
    def spawn_subprocess(recipe = @configuration, index: 0, restart_count: 0)
      GoodJob.run_lifecycle_hooks(:before_supervisor_fork)

      supervisor_pid = @supervisor_pid
      readiness_reader, readiness_writer = IO.pipe
      # Read ends of siblings' pipes are inherited by this fork; the child has no
      # use for them and must close them so it never keeps a sibling's pipe open.
      inherited_readers = @subprocesses.values.map(&:readiness_reader)
      pid = fork do
        # +fork+ preserves signal handlers, so the child would otherwise run the
        # supervisor's handlers until {GoodJob::Subprocess} installs its own
        # (which happens only after its Capsule has booted). Those handlers
        # mutate supervisor state that nothing in the child reads, so an
        # INT/TERM arriving mid-boot would be silently swallowed and the child
        # would never shut down.
        reset_signal_handlers
        readiness_reader.close
        inherited_readers.each { |reader| reader.close unless reader.closed? }
        # A replacement fork inherits the probe server's listening socket, which it
        # never serves; left open it would keep the port bound for this subprocess's
        # whole life, outliving a supervisor that died without releasing it.
        @probe_server&.close_socket
        GoodJob::Subprocess.new(configuration: recipe, index: index, supervisor_pid: supervisor_pid, readiness_writer: readiness_writer).run
      rescue StandardError => e
        GoodJob._on_thread_error(e)
        exit!(1)
      end

      # The supervisor keeps only the read end; closing the write end lets the read
      # end see EOF when the subprocess dies.
      readiness_writer.close
      @subprocesses[pid] = SubprocessHandle.new(pid: pid, index: index, recipe: recipe, restart_count: restart_count, readiness_reader: readiness_reader)
      ActiveSupport::Notifications.instrument("cluster_spawn.good_job", { pid: pid })
      pid
    end

    # Reaps any subprocesses that have exited and, unless the supervisor is
    # shutting down, forks a replacement for each from its original recipe. A
    # subprocess that exited too quickly to be considered healthy is replaced
    # with exponential backoff to avoid a hot crash-restart loop.
    # @return [void]
    def reap_and_replace
      loop do
        pid, status = ::Process.wait2(-1, ::Process::WNOHANG)
        break unless pid

        handle = forget_subprocess(pid)
        ActiveSupport::Notifications.instrument("cluster_reap.good_job", { pid: pid, status: status&.exitstatus, signal: status&.termsig })
        next if @stopped || handle.nil?

        restart_count = restart_count_after(handle)
        backoff(restart_count)
        break if @stopped # a shutdown signal arrived during the backoff

        spawn_subprocess(handle.recipe, index: handle.index, restart_count: restart_count)
      end
    rescue Errno::ECHILD
      # No child processes exist yet or any longer.
    end

    # The consecutive-fast-exit count to assign a subprocess's replacement: it
    # grows while a subprocess keeps exiting before {MIN_HEALTHY_UPTIME}, and
    # resets once a subprocess has run long enough to be considered healthy.
    # @param handle [SubprocessHandle]
    # @return [Integer]
    def restart_count_after(handle)
      handle.uptime < MIN_HEALTHY_UPTIME ? handle.restart_count + 1 : 0
    end

    # Waits (interruptibly) for the backoff delay appropriate to +restart_count+
    # before replacing a crash-looping subprocess. A shutdown signal cuts the
    # wait short and sets @stopped via {#process_signals}.
    # @param restart_count [Integer]
    # @return [void]
    def backoff(restart_count)
      delay = backoff_delay(restart_count)
      return if delay.zero?

      ActiveSupport::Notifications.instrument("cluster_backoff.good_job", { restart_count: restart_count, delay: delay })
      drain_self_pipe # discard stale wakeups so the delay is real
      # Draining also discards the wakeup a shutdown signal wrote, so process the
      # signals themselves (the authoritative record) before waiting; otherwise a
      # signal that arrived just before the drain would go unnoticed for the
      # entire delay.
      process_signals
      return if @stopped

      IO.select([@self_pipe_reader], nil, nil, delay)
      process_signals
    end

    # Exponential backoff (seconds) between replacements of a crash-looping
    # subprocess: 0 for a first fast exit, then MIN_BACKOFF_DELAY doubling up to
    # MAX_BACKOFF_DELAY.
    # @param restart_count [Integer]
    # @return [Integer]
    def backoff_delay(restart_count)
      return 0 if restart_count < 2

      [MIN_BACKOFF_DELAY * (2**(restart_count - 2)), MAX_BACKOFF_DELAY].min
    end

    # Signals all subprocesses to shut down and waits for them to exit,
    # escalating to +SIGKILL+ if a positive +timeout+ elapses.
    # @param timeout [nil, Numeric] +nil+ triggers but does not wait; a negative
    #   value waits forever; +0+ or a positive value waits that many seconds
    #   before killing survivors.
    # @return [void]
    def terminate_subprocesses(timeout)
      signal_subprocesses("TERM")

      if timeout.nil?
        nil
      elsif timeout.negative?
        reap_all_blocking
      elsif !reap_all_until(Supervisor.monotonic + escalation_timeout(timeout))
        signal_subprocesses("KILL")
        reap_all_blocking
      end
    end

    # Seconds to wait after +SIGTERM+ before escalating to +SIGKILL+. Each
    # subprocess drains for +timeout+, so the supervisor waits that long plus
    # {SHUTDOWN_GRACE} for it to actually exit; it never kills a subprocess that
    # is still within its own drain budget. Immediate shutdown (+0+) gets no grace.
    # @param timeout [Numeric] a non-negative drain timeout
    # @return [Numeric]
    def escalation_timeout(timeout)
      timeout.positive? ? timeout + SHUTDOWN_GRACE : timeout
    end

    # @param signal [String]
    # @return [void]
    def signal_subprocesses(signal)
      @subprocesses.each_key do |pid|
        ::Process.kill(signal, pid)
      rescue Errno::ESRCH
        # Already gone; it will be reaped.
      end
    end

    # Removes the subprocess's handle from the registry and closes the read end of
    # its readiness pipe, so the supervisor never leaks a descriptor for a
    # subprocess it is no longer tracking.
    # @param pid [Integer]
    # @return [SubprocessHandle, nil] the handle that was removed, if any.
    def forget_subprocess(pid)
      handle = @subprocesses.delete(pid)
      reader = handle&.readiness_reader
      reader.close if reader && !reader.closed?
      handle
    end

    # Blocks until every recorded subprocess has been reaped.
    # @return [void]
    def reap_all_blocking
      until @subprocesses.empty?
        begin
          pid, _status = ::Process.wait2
        rescue Errno::ECHILD
          break
        end
        forget_subprocess(pid)
      end
    end

    # Polls (non-blocking) until every subprocess is reaped or the deadline passes.
    # @param deadline [Time]
    # @return [Boolean] Whether all subprocesses exited before the deadline.
    def reap_all_until(deadline)
      loop do
        return true if @subprocesses.empty?

        begin
          pid, _status = ::Process.wait2(-1, ::Process::WNOHANG)
        rescue Errno::ECHILD
          return true
        end

        if pid
          forget_subprocess(pid)
        elsif Supervisor.monotonic >= deadline
          return false
        else
          sleep REAP_INTERVAL
        end
      end
    end

    # Drains signals received since the last iteration, updating shutdown state.
    # Ruby runs +trap+ blocks at VM safe points, so mutating state here is safe.
    # @return [void]
    def process_signals
      until @received_signals.empty?
        signal = @received_signals.shift
        if GRACEFUL_SIGNALS.include?(signal)
          @stopped = true
          @shutdown_timeout ||= @configuration.shutdown_timeout
        elsif IMMEDIATE_SIGNALS.include?(signal)
          @stopped = true
          @shutdown_timeout = 0
        end
      end
    end

    # Binds the probe/health-check port (in the supervisor process only) with a
    # cluster-aware Rack app. A configured +probe_app+ replaces it entirely, just
    # as it replaces the single-process health-check app. No-op unless a probe
    # port is configured.
    # @return [void]
    def start_probe_server
      return unless @configuration.probe_port

      @probe_server = GoodJob::ProbeServer.new(
        port: @configuration.probe_port,
        handler: @configuration.probe_handler,
        app: @configuration.probe_app || GoodJob::ProbeServer.cluster_app(self)
      )
      @probe_server.start
    end

    # @return [void]
    def stop_probe_server
      @probe_server&.stop
    end

    # @return [void]
    def install_signal_handlers
      (GRACEFUL_SIGNALS + IMMEDIATE_SIGNALS).each do |signal|
        trap(signal) do
          @received_signals << signal
          wake
        end
      end
      # Wake promptly to reap (and replace) a subprocess as soon as it exits.
      trap("CHLD") { wake }
    end

    # Wakes the supervise loop by writing to the self-pipe. Safe to call from a
    # +trap+ handler: a bare +IO#write_nonblock+ acquires no Ruby mutex, unlike
    # +Concurrent::Event#set+ (which raises "can't be called from trap context").
    # @return [void]
    def wake
      @self_pipe_writer.write_nonblock(".", exception: false)
    rescue IOError
      nil
    end

    # Blocks until the self-pipe becomes readable (a signal arrived) or the poll
    # interval elapses, then drains anything buffered in the pipe.
    # @return [void]
    def wait_for_wakeup
      # Wake on a signal (self-pipe) or a subprocess readiness heartbeat, so the
      # connected health check reflects readiness changes promptly rather than only
      # once per poll interval.
      readers = [@self_pipe_reader, *@subprocesses.values.filter_map(&:readiness_reader)]
      IO.select(readers, nil, nil, SUPERVISE_INTERVAL)
      drain_self_pipe
      refresh_readiness
    end

    # Reads each subprocess's readiness pipe (non-blocking) and records the time of
    # any readiness heartbeat, so {#connected?} can tell which subprocesses are
    # currently ready. Runs on the main thread; only mutates the thread-safe
    # per-handle readiness timestamp.
    # @return [void]
    def refresh_readiness
      now = Supervisor.monotonic
      @subprocesses.each_value do |handle|
        handle.mark_ready(now) if drain_readiness(handle.readiness_reader)
      end
    end

    # Drains a subprocess's readiness pipe without blocking.
    # @param reader [IO, nil]
    # @return [Boolean] Whether a readiness heartbeat was read.
    def drain_readiness(reader)
      return false if reader.nil? || reader.closed?

      read_any = false
      loop do
        reader.read_nonblock(256)
        read_any = true
      end
    rescue IO::WaitReadable
      read_any
    rescue IOError
      # EOF (the subprocess closed its end) or a closed pipe during shutdown; the
      # subprocess will be reaped and its handle removed.
      false
    end

    # Discards any bytes buffered in the self-pipe by signal handlers.
    # @return [void]
    def drain_self_pipe
      # read_nonblock raises IO::WaitReadable once the pipe is drained; IOError
      # (a superclass of EOFError) covers a closed pipe during shutdown.
      loop { @self_pipe_reader.read_nonblock(256) }
    rescue IO::WaitReadable, IOError
      nil
    end

    # Resets every signal the supervisor traps back to its default disposition.
    # Used both when the supervisor exits and immediately after a +fork+, so that
    # a child never inherits and runs the supervisor's handlers.
    # @return [void]
    def reset_signal_handlers
      (GRACEFUL_SIGNALS + IMMEDIATE_SIGNALS + %w[CHLD]).each do |signal|
        trap(signal, "DEFAULT")
      rescue ArgumentError
        # Signal not supported on this platform.
      end
    end
  end
end
