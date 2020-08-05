require "concurrent/executor/thread_pool_executor"
require "concurrent/timer_task"
require "concurrent/utility/processor_counter"

module GoodJob
  class Scheduler
    DEFAULT_TIMER_OPTIONS = {
      execution_interval: 1,
      timeout_interval: 1,
      run_now: true,
    }.freeze

    DEFAULT_POOL_OPTIONS = {
      name: 'good_job',
      min_threads: 0,
      max_threads: Concurrent.processor_count,
      auto_terminate: true,
      idletime: 60,
      max_queue: -1,
      fallback_policy: :discard,
    }.freeze

    def initialize(performer, timer_options: {}, pool_options: {})
      raise ArgumentError, "Performer argument must implement #next" unless performer.respond_to?(:next)

      @performer = performer
      @pool_options = DEFAULT_POOL_OPTIONS.merge(pool_options)
      @timer_options = DEFAULT_TIMER_OPTIONS.merge(timer_options)

      create_pools
    end

    def shutdown(wait: true)
      @_shutdown = true

      ActiveSupport::Notifications.instrument("scheduler_shutdown_start.good_job", { wait: wait })
      ActiveSupport::Notifications.instrument("scheduler_shutdown.good_job", { wait: wait }) do
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

    def shutdown?
      @_shutdown
    end

    def restart(wait: true)
      ActiveSupport::Notifications.instrument("scheduler_restart_pools.good_job") do
        shutdown(wait: wait) unless shutdown?
        create_pools
      end
    end

    def create_thread
      return false unless @pool.ready_worker_count.positive?

      future = Concurrent::Future.new(args: [@performer], executor: @pool) do |performer|
        output = nil
        Rails.application.executor.wrap { output = performer.next }
        output
      end
      future.add_observer(self, :task_observer)
      future.execute
    end

    def timer_observer(time, executed_task, thread_error)
      ActiveSupport::Notifications.instrument("finished_timer_task.good_job", { result: executed_task, error: thread_error, time: time })
    end

    def task_observer(time, output, thread_error)
      ActiveSupport::Notifications.instrument("finished_job_task.good_job", { result: output, error: thread_error, time: time })
      create_thread if output
    end

    class ThreadPoolExecutor < Concurrent::ThreadPoolExecutor
      # https://github.com/ruby-concurrency/concurrent-ruby/issues/684#issuecomment-427594437
      def ready_worker_count
        synchronize do
          workers_still_to_be_created = @max_length - @pool.length
          workers_created_but_waiting = @ready.length

          workers_still_to_be_created + workers_created_but_waiting
        end
      end
    end

    private

    def create_pools
      ActiveSupport::Notifications.instrument("scheduler_create_pools.good_job", { performer_name: @performer.name, max_threads: @pool_options[:max_threads], poll_interval: @timer_options[:execution_interval] }) do
        @pool = ThreadPoolExecutor.new(@pool_options)
        next unless @timer_options[:execution_interval].positive?

        @timer = Concurrent::TimerTask.new(@timer_options) { create_thread }
        @timer.add_observer(self, :timer_observer)
        @timer.execute
      end
    end
  end
end
