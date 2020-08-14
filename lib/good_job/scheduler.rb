require "concurrent/executor/thread_pool_executor"
require "concurrent/timer_task"
require "concurrent/utility/processor_counter"

module GoodJob # :nodoc:
  # Schedulers are generic thread execution pools that are responsible for
  # periodically checking for available execution tasks, executing tasks in a
  # bounded thread-pool, and efficiently scaling execution threads.
  #
  # Schedulers are "generic" in the sense that they delegate task execution
  # details to a "Performer" object that responds to #next.
  class Scheduler
    # Defaults for instance of Concurrent::TimerTask
    DEFAULT_TIMER_OPTIONS = {
      execution_interval: 1,
      timeout_interval: 1,
      run_now: true,
    }.freeze

    # Defaults for instance of Concurrent::ThreadPoolExecutor
    DEFAULT_POOL_OPTIONS = {
      name: 'good_job',
      min_threads: 0,
      max_threads: Concurrent.processor_count,
      auto_terminate: true,
      idletime: 60,
      max_queue: -1,
      fallback_policy: :discard,
    }.freeze

    # All instantiated Schedulers in the current process.
    # @!scope class
    # @!attribute [r] instances
    # @return [array<GoodJob:Scheduler>]
    cattr_reader :instances, default: [], instance_reader: false

    # Creates GoodJob::Scheduler(s) and Performers from a GoodJob::Configuration instance.
    # @param configuration [GoodJob::Configuration]
    # @return [GoodJob::Scheduler, GoodJob::MultiScheduler]
    def self.from_configuration(configuration)
      schedulers = configuration.queue_string.split(';').map do |queue_string_and_max_threads|
        queue_string, max_threads = queue_string_and_max_threads.split(':')
        max_threads = (max_threads || configuration.max_threads).to_i

        job_query = GoodJob::Job.queue_string(queue_string)
        job_performer = GoodJob::Performer.new(job_query, :perform_with_advisory_lock, name: queue_string)

        timer_options = {}
        timer_options[:execution_interval] = configuration.poll_interval if configuration.poll_interval.positive?

        pool_options = {
          max_threads: max_threads,
        }

        GoodJob::Scheduler.new(job_performer, timer_options: timer_options, pool_options: pool_options)
      end

      if schedulers.size > 1
        GoodJob::MultiScheduler.new(schedulers)
      else
        schedulers.first
      end
    end

    # @param performer [GoodJob::Performer]
    # @param timer_options [Hash] Options to instantiate a Concurrent::TimerTask
    # @param pool_options [Hash] Options to instantiate a Concurrent::ThreadPoolExecutor
    def initialize(performer, timer_options: {}, pool_options: {})
      raise ArgumentError, "Performer argument must implement #next" unless performer.respond_to?(:next)

      self.class.instances << self

      @performer = performer
      @pool_options = DEFAULT_POOL_OPTIONS.merge(pool_options)
      @timer_options = DEFAULT_TIMER_OPTIONS.merge(timer_options)

      create_pools
    end

    # Shut down the Scheduler.
    # @param wait [Boolean] Wait for actively executing jobs to finish
    # @return [void]
    def shutdown(wait: true)
      @_shutdown = true

      ActiveSupport::Notifications.instrument("scheduler_shutdown_start.good_job", { wait: wait, process_id: process_id })
      ActiveSupport::Notifications.instrument("scheduler_shutdown.good_job", { wait: wait, process_id: process_id }) do
        if @timer&.running?
          @timer.shutdown
          @timer.wait_for_termination if wait
        end

        if @pool&.running?
          @pool.shutdown
          @pool.wait_for_termination if wait
        end
      end
    end

    # True when the Scheduler is shutdown.
    # @return [true, false, nil]
    def shutdown?
      @_shutdown
    end

    # Restart the Scheduler. When shutdown, start; or shutdown and start.
    # @param wait [Boolean] Wait for actively executing jobs to finish
    # @return [void]
    def restart(wait: true)
      ActiveSupport::Notifications.instrument("scheduler_restart_pools.good_job", { process_id: process_id }) do
        shutdown(wait: wait) unless shutdown?
        create_pools
      end
    end

    # Triggers the execution the Performer, if an execution thread is available.
    # @return [Boolean]
    def create_thread
      return false unless @pool.ready_worker_count.positive?

      future = Concurrent::Future.new(args: [@performer], executor: @pool) do |performer|
        output = nil
        Rails.application.executor.wrap { output = performer.next }
        output
      end
      future.add_observer(self, :task_observer)
      future.execute
      true
    end

    # Invoked on completion of TimerTask task.
    # @!visibility private
    # @return [void]
    def timer_observer(time, executed_task, thread_error)
      GoodJob.on_thread_error.call(thread_error) if thread_error && GoodJob.on_thread_error.respond_to?(:call)
      ActiveSupport::Notifications.instrument("finished_timer_task.good_job", { result: executed_task, error: thread_error, time: time })
    end

    # Invoked on completion of ThreadPoolExecutor task
    # @!visibility private
    # @return [void]
    def task_observer(time, output, thread_error)
      GoodJob.on_thread_error.call(thread_error) if thread_error && GoodJob.on_thread_error.respond_to?(:call)
      ActiveSupport::Notifications.instrument("finished_job_task.good_job", { result: output, error: thread_error, time: time })
      create_thread if output
    end

    private

    # @return [void]
    def create_pools
      ActiveSupport::Notifications.instrument("scheduler_create_pools.good_job", { performer_name: @performer.name, max_threads: @pool_options[:max_threads], poll_interval: @timer_options[:execution_interval], process_id: process_id }) do
        @pool = ThreadPoolExecutor.new(@pool_options)
        next unless @timer_options[:execution_interval].positive?

        @timer = Concurrent::TimerTask.new(@timer_options) { create_thread }
        @timer.add_observer(self, :timer_observer)
        @timer.execute
      end
    end

    # @return [Integer] Current process ID
    def process_id
      Process.pid
    end

    # @return [String] Current thread name
    def thread_name
      (Thread.current.name || Thread.current.object_id).to_s
    end
  end

  # Slightly customized sub-class of Concurrent::ThreadPoolExecutor
  class ThreadPoolExecutor < Concurrent::ThreadPoolExecutor
    # Number of idle or potential threads available to execute tasks
    # https://github.com/ruby-concurrency/concurrent-ruby/issues/684#issuecomment-427594437
    # @return [Integer]
    def ready_worker_count
      synchronize do
        workers_still_to_be_created = @max_length - @pool.length
        workers_created_but_waiting = @ready.length

        workers_still_to_be_created + workers_created_but_waiting
      end
    end
  end
end
