# frozen_string_literal: true
require "concurrent/hash"
require "concurrent/scheduled_task"
require "fugit"

module GoodJob # :nodoc:
  #
  # CronManagers enqueue jobs on a repeating schedule.
  #
  class CronManager
    # @!attribute [r] instances
    #   @!scope class
    #   List of all instantiated CronManagers in the current process.
    #   @return [Array<GoodJob::CronManager>, nil]
    cattr_reader :instances, default: [], instance_reader: false

    # Task observer for cron task
    # @param time [Time]
    # @param output [Object]
    # @param thread_error [Exception]
    def self.task_observer(time, output, thread_error) # rubocop:disable Lint/UnusedMethodArgument
      return if thread_error.is_a? Concurrent::CancelledOperationError

      GoodJob.on_thread_error.call(thread_error) if thread_error && GoodJob.on_thread_error.respond_to?(:call)
    end

    # Execution configuration to be scheduled
    # @return [Hash]
    attr_reader :cron_entries

    # @param cron_entries [Array<CronEntry>]
    # @param start_on_initialize [Boolean]
    def initialize(cron_entries = [], start_on_initialize: false)
      @running = false
      @cron_entries = cron_entries
      @tasks = Concurrent::Hash.new

      self.class.instances << self

      start if start_on_initialize
    end

    # Schedule tasks that will enqueue jobs based on their schedule
    def start
      ActiveSupport::Notifications.instrument("cron_manager_start.good_job", cron_entries: cron_entries) do
        @running = true
        cron_entries.each do |cron_entry|
          create_task(cron_entry)
        end
      end
    end

    # Stop/cancel any scheduled tasks
    # @param timeout [Numeric, nil] Unused but retained for compatibility
    def shutdown(timeout: nil) # rubocop:disable Lint/UnusedMethodArgument
      @running = false
      @tasks.each do |_cron_key, task|
        task.cancel
      end
      @tasks.clear
    end

    # Stop and restart
    # @param timeout [Numeric, nil] Unused but retained for compatibility
    def restart(timeout: nil) # rubocop:disable Lint/UnusedMethodArgument
      shutdown
      start
    end

    # Tests whether the manager is running.
    # @return [Boolean, nil]
    def running?
      @running
    end

    # Tests whether the manager is shutdown.
    # @return [Boolean, nil]
    def shutdown?
      !running?
    end

    # Enqueues a scheduled task
    # @param cron_entry [CronEntry] the CronEntry object to schedule
    def create_task(cron_entry)
      cron_at = cron_entry.next_at
      delay = [(cron_at - Time.current).to_f, 0].max
      future = Concurrent::ScheduledTask.new(delay, args: [self, cron_entry, cron_at]) do |thr_scheduler, thr_cron_entry, thr_cron_at|
        # Re-schedule the next cron task before executing the current task
        thr_scheduler.create_task(thr_cron_entry)

        Rails.application.executor.wrap do
          CurrentThread.reset
          CurrentThread.cron_key = thr_cron_entry.key
          CurrentThread.cron_at = thr_cron_at

          cron_entry.enqueue
        end
      end

      @tasks[cron_entry.key] = future
      future.add_observer(self.class, :task_observer)
      future.execute
    end
  end
end
