# frozen_string_literal: true
require "concurrent/executor/timer_set"

module GoodJob
  class ProcessManager
    HEARTBEAT_INTERVAL = 1.minute
    EXPIRED_INTERVAL = 5.minutes

    # @!attribute [r] instances
    #   @!scope class
    #   List of all instantiated ProcessManagers in the current process.
    #   @return [Array<GoodJob::ProcessManager>, nil]
    cattr_reader :instances, default: [], instance_reader: false

    cattr_reader :mutex, default: Mutex.new
    cattr_accessor :_current_process_id, default: nil
    cattr_accessor :_pid, default: nil

    # UUID that is unique to the current process and changes when forked.
    # @return [String]
    def self.current_process_id
      return _current_process_id if _current_process_id && _pid == ::Process.pid

      mutex.synchronize do
        if _current_process_id.nil? || _pid != ::Process.pid
          self._current_process_id = SecureRandom.uuid
          self._pid = ::Process.pid
        end
        _current_process_id
      end
    end

    attr_reader :timer

    def initialize
      self.class.instances << self

      register
      create_timer
    end

    def register
      Rails.application.executor.wrap do
        Process.register
        Process.cleanup
      end
    end

    def heartbeat
      Rails.application.executor.wrap do
        Process.logger.silence do
          Process.register
          Process.cleanup
        end
      end
    end

    def unregister
      Rails.application.executor.wrap do
        Process.unregister
      end
    end

    def create_timer
      timer_options = {
        execution_interval: HEARTBEAT_INTERVAL,
      }

      @timer = Concurrent::TimerTask.new(timer_options) { heartbeat }
      @timer.add_observer(self, :timer_observer)
      @timer.execute
    end

    def timer_observer(_time, _executed_task, thread_error)
      GoodJob._on_thread_error(thread_error) if thread_error
    end

    # Tests whether the timer is running.
    # @return [true, false, nil]
    delegate :running?, to: :timer, allow_nil: true

    # Tests whether the timer is shutdown.
    # @return [true, false, nil]
    def shutdown?
      timer ? timer.shutdown? : true
    end

    # Shut down the poller.
    # Use {#shutdown?} to determine whether threads have stopped.
    # @param timeout [nil] Unused but kept for compatibility.
    # @return [void]
    def shutdown(timeout: nil) # rubocop:disable Lint/UnusedMethodArgument
      if timer.nil? || timer.shutdown?
        unregister
        return
      end
      timer.shutdown if timer.running?
      unregister
    end

    # Restart the poller.
    # When shutdown, start; or shutdown and start.
    # @param timeout [Numeric, nil] Seconds to wait; shares same values as {#shutdown}.
    # @return [void]
    def restart(timeout: -1)
      shutdown(timeout: timeout) if running?
      create_timer
    end
  end
end
