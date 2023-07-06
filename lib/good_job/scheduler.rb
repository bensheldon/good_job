# frozen_string_literal: true

require "concurrent/executor/thread_pool_executor"
require "concurrent/executor/timer_set"
require "concurrent/scheduled_task"
require "concurrent/utility/processor_counter"
require 'good_job/metrics'

module GoodJob # :nodoc:
  #
  # Schedulers are generic thread pools that are responsible for
  # periodically checking for available tasks, executing tasks within a thread,
  # and efficiently scaling active threads.
  #
  # Every scheduler has a single {JobPerformer} that will execute tasks.
  # The scheduler is responsible for calling its performer efficiently across threads managed by an instance of +Concurrent::ThreadPoolExecutor+.
  # If a performer does not have work, the thread will go to sleep.
  # The scheduler maintains an instance of +Concurrent::TimerTask+, which wakes sleeping threads and causes them to check whether the performer has new work.
  #
  class Scheduler
    # Defaults for instance of Concurrent::ThreadPoolExecutor
    # The thread pool executor is where work is performed.
    DEFAULT_EXECUTOR_OPTIONS = {
      name: name,
      min_threads: 0,
      max_threads: Configuration::DEFAULT_MAX_THREADS,
      auto_terminate: true,
      idletime: 60,
      max_queue: Configuration::DEFAULT_MAX_THREADS,
      fallback_policy: :discard,
    }.freeze

    # @!attribute [r] instances
    #   @!scope class
    #   List of all instantiated Schedulers in the current process.
    #   @return [Array<GoodJob::Scheduler>, nil]
    cattr_reader :instances, default: Concurrent::Array.new, instance_reader: false

    # Creates GoodJob::Scheduler(s) and Performers from a GoodJob::Configuration instance.
    # @param configuration [GoodJob::Configuration]
    # @param warm_cache_on_initialize [Boolean]
    # @return [GoodJob::Scheduler, GoodJob::MultiScheduler]
    def self.from_configuration(configuration, capsule: GoodJob.capsule, warm_cache_on_initialize: false)
      schedulers = configuration.queue_string.split(';').map do |queue_string_and_max_threads|
        queue_string, max_threads = queue_string_and_max_threads.split(':')
        max_threads = (max_threads || configuration.max_threads).to_i

        job_performer = GoodJob::JobPerformer.new(queue_string, capsule: capsule)
        GoodJob::Scheduler.new(
          job_performer,
          max_threads: max_threads,
          max_cache: configuration.max_cache,
          warm_cache_on_initialize: warm_cache_on_initialize,
          cleanup_interval_seconds: configuration.cleanup_interval_seconds,
          cleanup_interval_jobs: configuration.cleanup_interval_jobs
        )
      end

      if schedulers.size > 1
        GoodJob::MultiScheduler.new(schedulers)
      else
        schedulers.first
      end
    end

    # Human readable name of the scheduler that includes configuration values.
    # @return [String]
    attr_reader :name

    # @param performer [GoodJob::JobPerformer]
    # @param max_threads [Numeric, nil] number of seconds between polls for jobs
    # @param max_cache [Numeric, nil] maximum number of scheduled jobs to cache in memory
    # @param warm_cache_on_initialize [Boolean] whether to warm the cache immediately, or manually by calling +warm_cache+
    # @param cleanup_interval_seconds [Numeric, nil] number of seconds between cleaning up job records
    # @param cleanup_interval_jobs [Numeric, nil] number of executed jobs between cleaning up job records
    def initialize(performer, max_threads: nil, max_cache: nil, warm_cache_on_initialize: false, cleanup_interval_seconds: nil, cleanup_interval_jobs: nil)
      raise ArgumentError, "Performer argument must implement #next" unless performer.respond_to?(:next)

      @performer = performer

      @max_cache = max_cache || 0
      @executor_options = DEFAULT_EXECUTOR_OPTIONS.dup
      if max_threads.present?
        @executor_options[:max_threads] = max_threads
        @executor_options[:max_queue] = max_threads
      end
      @name = "GoodJob::Scheduler(queues=#{@performer.name} max_threads=#{@executor_options[:max_threads]})"
      @executor_options[:name] = name

      @cleanup_tracker = CleanupTracker.new(cleanup_interval_seconds: cleanup_interval_seconds, cleanup_interval_jobs: cleanup_interval_jobs)
      @metrics = ::GoodJob::Metrics.new
      @executor_options[:name] = name

      create_executor
      warm_cache if warm_cache_on_initialize
      self.class.instances << self
    end

    # Tests whether the scheduler is running.
    # @return [Boolean, nil]
    delegate :running?, to: :executor, allow_nil: true

    # Tests whether the scheduler is shutdown.
    # @return [Boolean, nil]
    delegate :shutdown?, to: :executor, allow_nil: true

    # Shut down the scheduler.
    # This stops all threads in the thread pool.
    # Use {#shutdown?} to determine whether threads have stopped.
    # @param timeout [Numeric, nil] Seconds to wait for actively executing jobs to finish
    #   * +nil+, the scheduler will trigger a shutdown but not wait for it to complete.
    #   * +-1+, the scheduler will wait until the shutdown is complete.
    #   * +0+, the scheduler will immediately shutdown and stop any active tasks.
    #   * A positive number will wait that many seconds before stopping any remaining active tasks.
    # @return [void]
    def shutdown(timeout: -1)
      return if executor.nil? || executor.shutdown?

      instrument("scheduler_shutdown_start", { timeout: timeout })
      instrument("scheduler_shutdown", { timeout: timeout }) do
        if executor.running?
          @timer_set.shutdown
          executor.shutdown
        end

        if executor.shuttingdown? && timeout
          executor_wait = timeout.negative? ? nil : timeout

          unless executor.wait_for_termination(executor_wait)
            instrument("scheduler_shutdown_kill", { active_job_ids: @performer.performing_active_job_ids.to_a })
            executor.kill
          end
        end
      end
    end

    # Restart the Scheduler.
    # When shutdown, start; or shutdown and start.
    # @param timeout [Numeric] Seconds to wait for actively executing jobs to finish; shares same values as {#shutdown}.
    # @return [void]
    def restart(timeout: -1)
      raise ArgumentError, "Scheduler#restart cannot be called with a timeout of nil" if timeout.nil?

      instrument("scheduler_restart_pools") do
        shutdown(timeout: timeout)
        @metrics.reset
        create_executor
        warm_cache
      end
    end

    # Wakes a thread to allow the performer to execute a task.
    # @param state [Hash, nil] Contextual information for the performer. See {JobPerformer#next?}.
    # @return [Boolean, nil] Whether work was started.
    #
    #   * +nil+ if the scheduler is unable to take new work, for example if the thread pool is shut down or at capacity.
    #   * +true+ if the performer started executing work.
    #   * +false+ if the performer decides not to attempt to execute a task based on the +state+ that is passed to it.
    def create_thread(state = nil)
      return nil unless executor.running?

      if state
        return false unless performer.next?(state)

        if state[:count]
          # When given state for multiple jobs, try to create a thread for each one.
          # Return true if a thread can be created for all of them, nil if partial or none.

          state_without_count = state.without(:count)
          result = state[:count].times do
            value = create_thread(state_without_count)
            break(value) unless value
          end

          return result.nil? ? nil : true
        end

        if state[:scheduled_at]
          scheduled_at = if state[:scheduled_at].is_a? String
                           Time.zone.parse state[:scheduled_at]
                         else
                           state[:scheduled_at]
                         end
          delay = [(scheduled_at - Time.current).to_f, 0].max
        end
      end

      delay ||= 0
      run_now = delay <= 0.01
      if run_now
        return nil unless executor.ready_worker_count.positive?
      elsif @max_cache.positive?
        return nil unless remaining_cache_count.positive?
      end

      create_task(delay)

      run_now ? true : nil
    end

    # Invoked on completion of ThreadPoolExecutor task
    # @!visibility private
    # @return [void]
    def task_observer(time, output, thread_error)
      result = output.is_a?(GoodJob::ExecutionResult) ? output : nil

      unhandled_error = thread_error || result&.unhandled_error
      GoodJob._on_thread_error(unhandled_error) if unhandled_error

      if unhandled_error || result&.handled_error
        @metrics.increment_errored_executions
      elsif result&.unexecutable
        @metrics.increment_unexecutable_executions
      elsif result
        @metrics.increment_succeeded_executions
      else
        @metrics.increment_empty_executions
      end

      instrument("finished_job_task", { result: output, error: thread_error, time: time })
      return unless output

      @cleanup_tracker.increment
      if @cleanup_tracker.cleanup?
        cleanup
      else
        create_task
      end
    end

    # Information about the Scheduler
    # @return [Hash]
    def stats
      available_threads = executor.ready_worker_count
      {
        name: name,
        queues: performer.name,
        max_threads: @executor_options[:max_threads],
        active_threads: @executor_options[:max_threads] - available_threads,
        available_threads: available_threads,
        max_cache: @max_cache,
        active_cache: cache_count,
        available_cache: remaining_cache_count,
      }.merge!(@metrics.to_h)
    end

    # Preload existing runnable and future-scheduled jobs
    # @return [void]
    def warm_cache
      return if @max_cache.zero?

      future = Concurrent::Future.new(args: [self, @performer], executor: executor) do |thr_scheduler, thr_performer|
        Rails.application.executor.wrap do
          thr_performer.next_at(
            limit: @max_cache,
            now_limit: @executor_options[:max_threads]
          ).each do |scheduled_at|
            thr_scheduler.create_thread({ scheduled_at: scheduled_at })
          end
        end
      end

      observer = lambda do |_time, _output, thread_error|
        GoodJob._on_thread_error(thread_error) if thread_error
        create_task # If cache-warming exhausts the threads, ensure there isn't an executable task remaining
      end
      future.add_observer(observer, :call)
      future.execute
    end

    # Preload existing runnable and future-scheduled jobs
    # @return [void]
    def cleanup
      @cleanup_tracker.reset

      future = Concurrent::Future.new(args: [self, @performer], executor: executor) do |_thr_scheduler, thr_performer|
        Rails.application.executor.wrap do
          thr_performer.cleanup
        end
      end

      observer = lambda do |_time, _output, thread_error|
        GoodJob._on_thread_error(thread_error) if thread_error
        create_task
      end
      future.add_observer(observer, :call)
      future.execute
    end

    private

    attr_reader :performer, :executor, :timer_set

    # @return [void]
    def create_executor
      instrument("scheduler_create_pool", { performer_name: performer.name, max_threads: @executor_options[:max_threads] }) do
        @timer_set = TimerSet.new
        @executor = ThreadPoolExecutor.new(@executor_options)
      end
    end

    # @param delay [Integer]
    # @return [void]
    def create_task(delay = 0)
      future = Concurrent::ScheduledTask.new(delay, args: [performer], executor: executor, timer_set: timer_set) do |thr_performer|
        Thread.current.name = Thread.current.name.sub("-worker-", "-thread-") if Thread.current.name
        Rails.application.reloader.wrap do
          thr_performer.next
        end
      end
      future.add_observer(self, :task_observer)
      future.execute
    end

    # @param name [String]
    # @param payload [Hash]
    # @return [void]
    def instrument(name, payload = {}, &block)
      payload = payload.reverse_merge({
                                        scheduler: self,
                                        process_id: GoodJob::CurrentThread.process_id,
                                        thread_name: GoodJob::CurrentThread.thread_name,
                                      })

      ActiveSupport::Notifications.instrument("#{name}.good_job", payload, &block)
    end

    def cache_count
      timer_set.length
    end

    def remaining_cache_count
      @max_cache - cache_count
    end

    # Custom sub-class of +Concurrent::ThreadPoolExecutor+ to add additional worker status.
    # @private
    class ThreadPoolExecutor < ::Concurrent::ThreadPoolExecutor
      # Number of inactive threads available to execute tasks.
      # https://github.com/ruby-concurrency/concurrent-ruby/issues/684#issuecomment-427594437
      # @return [Integer]
      def ready_worker_count
        synchronize do
          if Concurrent.on_jruby?
            @executor.getMaximumPoolSize - @executor.getActiveCount
          else
            workers_still_to_be_created = @max_length - @pool.length
            workers_created_but_waiting = @ready.length
            workers_still_to_be_created + workers_created_but_waiting
          end
        end
      end
    end

    # Custom sub-class of +Concurrent::TimerSet+ for additional behavior.
    # @private
    class TimerSet < ::Concurrent::TimerSet
      # Number of scheduled jobs in the queue
      # @return [Integer]
      def length
        @queue.length
      end

      # Clear the queue
      # @return [void]
      def reset
        synchronize { @queue.clear }
      end
    end
  end
end
