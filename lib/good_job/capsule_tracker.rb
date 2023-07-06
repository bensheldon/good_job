# frozen_string_literal: true

module GoodJob # :nodoc:
  # CapsuleTracker save a record in the database and periodically refreshes it. The intention is to
  # create a heartbeat that can be used to determine whether a capsule/process is still active
  # and use that to lock (or unlock) jobs.
  class CapsuleTracker
    # The database record used for tracking.
    # @return [GoodJob::CapsuleRecord, nil]
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
      @monitor = Monitor.new
      @locks = 0
      @advisory_locked_connection = nil
      @ruby_pid = ::Process.pid
      @record_id = SecureRandom.uuid
      @record = nil
      @refresh_task = nil

      self.class.instances << self
    end

    # The expected UUID of the process for use in inspection.
    # Use {#id_for_lock} if using this as a lock key.
    # @return [String]
    def process_id
      @record_id
    end

    # The UUID to use for locking. May be nil if the process is not registered or is unusable/expired.
    # If UUID has not yet been persisted to the database, this method will make a query to insert or update it.
    # @return [String, nil]
    def id_for_lock
      synchronize do
        next if @locks.zero?

        reset_on_fork
        Rails.application.executor.wrap do
          if @record
            @record.refresh_if_stale
          else
            @record = GoodJob::CapsuleRecord.create_record(id: @record_id)
            create_refresh_task
          end
          @record&.id
        end
      end
    end

    # Tests whether an active advisory lock has been taken on the record.
    # @return [Boolean]
    def advisory_locked?
      @advisory_locked_connection&.weakref_alive? && @advisory_locked_connection&.active?
    end

    # Registers the current process around a job execution site.
    # +register+ is expected to be called multiple times in a process, but should be advisory locked only once (in a single thread).
    # @param with_advisory_lock [Boolean] Whether the lock strategy should us an advisory lock; the connection must be retained to support advisory locks.
    # @yield [void] If a block is given, the process will be unregistered after the block completes.
    # @return [void]
    def register(with_advisory_lock: false)
      synchronize do
        if with_advisory_lock
          Rails.application.executor.wrap do
            if @record
              if !advisory_locked? || !advisory_locked_connection?
                @record.class.transaction do
                  @record.advisory_lock!
                  @record.update(lock_type: GoodJob::CapsuleRecord::LOCK_TYPE_ADVISORY)
                end
                @advisory_locked_connection = WeakRef.new(@record.class.connection)
              end
            else
              @record = GoodJob::CapsuleRecord.create_record(id: @record_id, with_advisory_lock: true)
              @advisory_locked_connection = WeakRef.new(@record.class.connection)
              create_refresh_task
            end
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
          Rails.application.executor.wrap do
            if @record
              if with_advisory_lock && advisory_locked? && advisory_locked_connection?
                @record.class.transaction do
                  @record.advisory_unlock
                  @record.cleanup
                end
                @advisory_locked_connection = nil
              else
                @record.cleanup
              end
              @record = nil
            end
          end
          cancel_refresh_task
        elsif with_advisory_lock && advisory_locked? && advisory_locked_connection?
          Rails.application.executor.wrap do
            @record.class.transaction do
              @record.advisory_unlock
              @record.update(lock_type: nil)
            end
            @advisory_locked_connection = nil
          end
        end

        @locks -= 1 unless @locks.zero?
      end
    end

    # Refreshes the process record in the database.
    # @param silent [Boolean] Whether to silence logging.
    # @return [void]
    def refresh(silent: false)
      Rails.application.executor.wrap do
        GoodJob::CapsuleRecord.with_logger_silenced(silent: silent) do
          @record&.refresh_if_stale(cleanup: true)
        end
      end
    end

    # @!visibility private
    def task_observer(_time, _output, thread_error)
      GoodJob._on_thread_error(thread_error) if thread_error && !thread_error.is_a?(Concurrent::CancelledOperationError)
    end

    private

    delegate :synchronize, to: :@monitor

    def advisory_locked_connection?
      @record&.class&.connection && @advisory_locked_connection&.weakref_alive? && @advisory_locked_connection.eql?(@record.class.connection)
    end

    def task_interval
      GoodJob::CapsuleRecord::STALE_INTERVAL + jitter
    end

    def jitter
      GoodJob::CapsuleRecord::STALE_INTERVAL * 0.1 * Kernel.rand
    end

    def create_refresh_task(delay: nil)
      return if @refresh_task

      delay ||= task_interval
      @refresh_task = Concurrent::ScheduledTask.new(delay.to_f, executor: @executor) do
        synchronize do
          next unless @locks.positive?

          create_refresh_task
          refresh(silent: true)
        end
      end
      @refresh_task.add_observer(self, :task_observer)
      @refresh_task.execute
    end

    def cancel_refresh_task
      @refresh_task&.cancel
      @refresh_task = nil
    end

    def reset_on_fork
      return if @ruby_pid == ::Process.pid

      @ruby_pid = ::Process.pid
      @record_id = SecureRandom.uuid
      @record = nil
    end
  end
end
