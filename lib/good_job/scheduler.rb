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
      @timer.add_observer(self, :timer_observer)
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
        good_job = nil

        Rails.application.executor.wrap do
          query.limit(1).with_advisory_lock do |good_jobs|
            good_job = good_jobs.first
            break unless good_job

            good_job.perform
          end
        end

        good_job
      end
      future.add_observer(self, :task_observer)
      future.execute
    end

    def timer_observer(time, executed_task, error)
      ActiveSupport::Notifications.instrument("finished_timer_task.good_job", { result: executed_task, error: error, time: time })
    end

    def task_observer(time, performed_job, error)
      ActiveSupport::Notifications.instrument("finished_job_task.good_job", { good_job: performed_job, error: error, time: time })
      create_thread if performed_job
    end
  end
end
