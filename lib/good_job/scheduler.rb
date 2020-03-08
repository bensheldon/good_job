require "concurrent/scheduled_task"
require "concurrent/executor/thread_pool_executor"
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
      idletime: 0,
      max_queue: 0,
      fallback_policy: :abort, # shouldn't matter -- 0 max queue
    }.freeze

    def initialize(query = GoodJob::Job.all, timer_options: {}, pool_options: {})
      @query = query

      @pool = Concurrent::ThreadPoolExecutor.new(DEFAULT_POOL_OPTIONS.merge(pool_options))
      @timer = Concurrent::TimerTask.new(DEFAULT_TIMER_OPTIONS.merge(timer_options)) do
        idle_threads = @pool.max_length - @pool.length
        create_thread if idle_threads.positive?
      end
      @timer.add_observer(TimerObserver.new)
      @timer.execute
    end

    def ordered_query
      @query.where("scheduled_at < ?", Time.current).or(@query.where(scheduled_at: nil)).order(priority: :desc)
    end

    def execute
    end

    def shutdown(wait: true)
      @_shutdown = true

      ActiveSupport::Notifications.instrument("scheduler_start_shutdown.good_job", { wait: wait })
      ActiveSupport::Notifications.instrument("scheduler_shutdown.good_job", { wait: wait }) do
        if @timer.running?
          @timer.shutdown
          @timer.wait_for_termination if wait
        end

        if @pool.running?
          @pool.shutdown
          @pool.wait_for_termination if wait
        end
      end
    end

    def shutdown?
      @_shutdown
    end

    def create_thread
      future = Concurrent::Future.new(args: [ordered_query], executor: @pool) do |query|
        loop do
          executed_job = false

          Rails.application.executor.wrap do
            good_job = query.with_advisory_lock.first
            break unless good_job

            executed_job = true
            ActiveSupport::Notifications.instrument("job_started.good_job", { good_job: good_job })
            JobWrapper.new(good_job).perform
            good_job.advisory_unlock
          end

          break unless executed_job
        end
      end
      future.add_observer(TaskObserver.new)
      future.execute
    end

    class TimerObserver
      def update(time, result, error)
        ActiveSupport::Notifications.instrument("timer_task_finished.good_job", { result: result, error: error, time: time })
      end
    end

    class TaskObserver
      def update(time, result, error)
        ActiveSupport::Notifications.instrument("job_finished.good_job", { result: result, error: error, time: time })
      end
    end
  end
end
