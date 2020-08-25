require "concurrent/executor/thread_pool_executor"
require "concurrent/timer_task"
require "concurrent/utility/processor_counter"

module GoodJob # :nodoc:
  #
  # Schedulers are generic thread execution pools that are responsible for
  # periodically checking for available execution tasks, executing tasks in a
  # bounded thread-pool, and efficiently scaling execution threads.
  #
  # Schedulers are "generic" in the sense that they delegate task execution
  # details to a "Performer" object that responds to #next.
  #
  class Scheduler
    # Defaults for instance of Concurrent::TimerTask
    DEFAULT_TIMER_OPTIONS = {
      execution_interval: 1,
      timeout_interval: 1,
      run_now: true,
    }.freeze

    # Defaults for instance of Concurrent::ThreadPoolExecutor
    DEFAULT_POOL_OPTIONS = {
      min_threads: 0,
      max_threads: Concurrent.processor_count,
      auto_terminate: true,
      idletime: 60,
      max_queue: -1,
      fallback_policy: :discard,
    }.freeze

    # @!attribute [r] instances
    #   @!scope class
    #   All instantiated Schedulers in the current process.
    #   @return [array<GoodJob:Scheduler>]
    cattr_reader :instances, default: [], instance_reader: false

    # Creates GoodJob::Scheduler(s) and Performers from a GoodJob::Configuration instance.
    # @param configuration [GoodJob::Configuration]
    # @return [GoodJob::Scheduler, GoodJob::MultiScheduler]
    def self.from_configuration(configuration)
      schedulers = configuration.queue_string.split(';').map do |queue_string_and_max_threads|
        queue_string, max_threads = queue_string_and_max_threads.split(':')
        max_threads = (max_threads || configuration.max_threads).to_i

        job_query = GoodJob::Job.queue_string(queue_string)
        parsed = GoodJob::Job.queue_parser(queue_string)
        job_filter = proc do |state|
          if parsed[:exclude]
            !parsed[:exclude].include? state[:queue_name]
          elsif parsed[:include]
            parsed[:include].include? state[:queue_name]
          else
            true
          end
        end
        job_performer = GoodJob::Performer.new(job_query, :perform_with_advisory_lock, name: queue_string, filter: job_filter)

        timer_options = {}
        timer_options[:execution_interval] = configuration.poll_interval

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

      @pool_options[:name] = "GoodJob::Scheduler(queues=#{@performer.name} max_threads=#{@pool_options[:max_threads]} poll_interval=#{@timer_options[:execution_interval]})"

      create_pools
    end

    # Shut down the Scheduler.
    # @param wait [Boolean] Wait for actively executing jobs to finish
    # @return [void]
    def shutdown(wait: true)
      @_shutdown = true

      instrument("scheduler_shutdown_start", { wait: wait })
      instrument("scheduler_shutdown", { wait: wait }) do
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
      instrument("scheduler_restart_pools") do
        shutdown(wait: wait) unless shutdown?
        create_pools
        @_shutdown = false
      end
    end

    # Triggers a Performer execution, if an execution thread is available.
    # @param state [nil, Object] Allows Performer#next? to accept or reject the execution
    # @return [nil, Boolean] if the thread was created
    def create_thread(state = nil)
      return nil unless @pool.running? && @pool.ready_worker_count.positive?

      if state
        return false unless @performer.next?(state)
      end

      future = Concurrent::Future.new(args: [@performer], executor: @pool) do |performer|
        performer.next
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
      instrument("finished_timer_task", { result: executed_task, error: thread_error, time: time })
    end

    # Invoked on completion of ThreadPoolExecutor task
    # @!visibility private
    # @return [void]
    def task_observer(time, output, thread_error)
      GoodJob.on_thread_error.call(thread_error) if thread_error && GoodJob.on_thread_error.respond_to?(:call)
      instrument("finished_job_task", { result: output, error: thread_error, time: time })
      create_thread if output
    end

    private

    # @return [void]
    def create_pools
      instrument("scheduler_create_pools", { performer_name: @performer.name, max_threads: @pool_options[:max_threads], poll_interval: @timer_options[:execution_interval] }) do
        @pool = ThreadPoolExecutor.new(@pool_options)
        next unless @timer_options[:execution_interval].positive?

        @timer = Concurrent::TimerTask.new(@timer_options) { create_thread }
        @timer.add_observer(self, :timer_observer)
        @timer.execute
      end
    end

    def instrument(name, payload = {}, &block)
      payload = payload.reverse_merge({
                                        scheduler: self,
                                        process_id: GoodJob::CurrentExecution.process_id,
                                        thread_name: GoodJob::CurrentExecution.thread_name,
                                      })

      ActiveSupport::Notifications.instrument("#{name}.good_job", payload, &block)
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
