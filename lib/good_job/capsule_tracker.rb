# frozen_string_literal: true

module GoodJob # :nodoc:
  # CapsuleTracker save a record in the database and periodically refreshes it. The intention is to
  # create a heartbeat that can be used to determine whether a capsule/process is still active
  # and use that to lock (or unlock) jobs.
  class CapsuleTracker
    # The database record used for tracking.
    # @return [GoodJob::Process, nil]
    attr_reader :record

    # Number of tracked job executions.
    attr_reader :locks

    # Number of tracked job executions with advisory locks.
    # @return [Integer]
    attr_reader :advisory_locks

    # @!attribute [r] instances
    #   @!scope class
    #   List of all instantiated CapsuleTrackers in the current process.
    #   @return [Array<GoodJob::CapsuleTracker>, nil]
    cattr_reader :instances, default: Concurrent::Array.new, instance_reader: false

    # @param executor [Concurrent::AbstractExecutorService] The executor to use for refreshing the process record.
    def initialize(executor: Concurrent.global_io_executor)
      @executor = executor
      @mutex = Mutex.new
      @locks = 0
      @advisory_locked_connection = nil
      @record_id = SecureRandom.uuid
      @record = nil
      @refresh_task = nil

      # AS::ForkTracker is only present on Rails v6.1+.
      # Fall back to PID checking if ForkTracker is not available
      if defined?(ActiveSupport::ForkTracker)
        ActiveSupport::ForkTracker.after_fork { reset }
        @forktracker = true
      else
        @ruby_pid = ::Process.pid
        @forktracker = false
      end

      self.class.instances << self
    end

    # The UUID to use for locking. May be nil if the process is not registered or is unusable/expired.
    # If UUID has not yet been persisted to the database, this method will make a query to insert or update it.
    # @return [String, nil]
    def id_for_lock
      value = nil
      synchronize do
        next if @locks.zero?

        reset_on_fork
        if @record
          @record.refresh_if_stale
        else
          @record = GoodJob::Process.create_record(id: @record_id)
          create_refresh_task
        end
        value = @record&.id
      end
      value
    end

    # The expected UUID of the process for use in inspection.
    # Use {#id_for_lock} if using this as a lock key.
    # @return [String]
    def process_id
      @record_id
    end

    # Registers the current process around a job execution site.
    # +register+ is expected to be called multiple times in a process, but should be advisory locked only once (in a single thread).
    # @param with_advisory_lock [Boolean] Whether the lock strategy should us an advisory lock; the connection must be retained to support advisory locks.
    # @yield [void] If a block is given, the process will be unregistered after the block completes.
    # @return [void]
    def register(with_advisory_lock: false)
      synchronize do
        if with_advisory_lock
          if @record
            if !advisory_locked? || !advisory_locked_connection?
              @record.class.transaction do
                @record.advisory_lock!
                @record.update(lock_type: GoodJob::Process::LOCK_TYPE_ADVISORY)
              end
              @advisory_locked_connection = WeakRef.new(@record.class.connection)
            end
          else
            @record = GoodJob::Process.create_record(id: @record_id, with_advisory_lock: true)
            @advisory_locked_connection = WeakRef.new(@record.class.connection)
            create_refresh_task
          end
        end

        @locks += 1
      end
      return unless block_given?

      begin
        yield
      ensure
        unregister(with_advisory_lock: with_advisory_lock)
      end
    end

    # Unregisters the current process from the database.
    # @param with_advisory_lock [Boolean] Whether the lock strategy should unlock an advisory lock; the connection must be able to support advisory locks.
    # @return [void]
    def unregister(with_advisory_lock: false)
      synchronize do
        if @locks.zero?
          return
        elsif @locks == 1
          if @record
            if with_advisory_lock && advisory_locked? && advisory_locked_connection?
              @record.class.transaction do
                @record.advisory_unlock
                @record.destroy
              end
              @advisory_locked_connection = nil
            else
              @record.destroy
            end
            @record = nil
          end
          cancel_refresh_task
        elsif with_advisory_lock && advisory_locked? && advisory_locked_connection?
          @record.class.transaction do
            @record.advisory_unlock
            @record.update(lock_type: nil)
          end
          @advisory_locked_connection = nil
        end

        @locks -= 1 unless @locks.zero?
      end
    end

    # Refreshes the process record in the database.
    # @param silent [Boolean] Whether to silence logging.
    # @return [void]
    def renew(silent: false)
      GoodJob::Process.with_logger_silenced(silent: silent) do
        @record&.refresh_if_stale(cleanup: true)
      end
    end

    # Tests whether an active advisory lock has been taken on the record.
    # @return [Boolean]
    def advisory_locked?
      @advisory_locked_connection&.weakref_alive? && @advisory_locked_connection&.active?
    end

    # @!visibility private
    def task_observer(_time, _output, thread_error)
      GoodJob._on_thread_error(thread_error) if thread_error && !thread_error.is_a?(Concurrent::CancelledOperationError)
    end

    private

    def advisory_locked_connection?
      @record&.class&.connection && @advisory_locked_connection&.weakref_alive? && @advisory_locked_connection.eql?(@record.class.connection)
    end

    def task_interval
      GoodJob::Process::STALE_INTERVAL + jitter
    end

    def jitter
      GoodJob::Process::STALE_INTERVAL * 0.1 * Kernel.rand
    end

    def create_refresh_task(delay: nil)
      return if @refresh_task
      return unless @executor

      delay ||= task_interval
      @refresh_task = Concurrent::ScheduledTask.new(delay.to_f, executor: @executor) do
        Rails.application.executor.wrap do
          synchronize do
            next unless @locks.positive?

            @refresh_task = nil
            create_refresh_task
            renew(silent: true)
          end
        end
      end
      @refresh_task.add_observer(self, :task_observer)
      @refresh_task.execute
    end

    def cancel_refresh_task
      @refresh_task&.cancel
      @refresh_task = nil
    end

    def reset
      synchronize { ns_reset }
    end

    def reset_on_fork
      return if Concurrent.on_jruby?
      return if @forktracker || ::Process.pid == @ruby_pid

      @ruby_pid = ::Process.pid
      ns_reset
    end

    def ns_reset
      @record_id = SecureRandom.uuid
      @record = nil
    end

    # Synchronize must always be called from within a Rails Executor; it may deadlock if the order is reversed.
    def synchronize(&block)
      if @mutex.owned?
        yield
      else
        @mutex.synchronize(&block)
      end
    end
  end
end
