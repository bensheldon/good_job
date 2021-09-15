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
    #   @return [Array<GoodJob::CronManagers>, nil]
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
    attr_reader :schedules

    # @param schedules [Hash]
    # @param start_on_initialize [Boolean]
    def initialize(schedules = {}, start_on_initialize: false)
      @running = false
      @schedules = schedules
      @tasks = Concurrent::Hash.new

      self.class.instances << self

      start if start_on_initialize
    end

    # Schedule tasks that will enqueue jobs based on their schedule
    def start
      ActiveSupport::Notifications.instrument("cron_manager_start.good_job", cron_jobs: @schedules) do
        @running = true
        schedules.each_key { |cron_key| create_task(cron_key) }
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
    # @param cron_key [Symbol, String] the key within the schedule to use
    def create_task(cron_key)
      schedule = @schedules[cron_key]
      return false if schedule.blank?

      fugit = Fugit::Cron.parse(schedule.fetch(:cron))
      delay = [(fugit.next_time - Time.current).to_f, 0].max

      future = Concurrent::ScheduledTask.new(delay, args: [self, cron_key]) do |thr_scheduler, thr_cron_key|
        # Re-schedule the next cron task before executing the current task
        thr_scheduler.create_task(thr_cron_key)

        CurrentThread.reset
        CurrentThread.cron_key = thr_cron_key

        Rails.application.executor.wrap do
          schedule = thr_scheduler.schedules.fetch(thr_cron_key).with_indifferent_access
          job_class = schedule.fetch(:class).constantize

          job_set_value = schedule.fetch(:set, {})
          job_set = job_set_value.respond_to?(:call) ? job_set_value.call : job_set_value

          job_args_value = schedule.fetch(:args, [])
          job_args = job_args_value.respond_to?(:call) ? job_args_value.call : job_args_value

          job_class.set(job_set).perform_later(*job_args)
        end
      end

      @tasks[cron_key] = future
      future.add_observer(self.class, :task_observer)
      future.execute
    end
  end
end
