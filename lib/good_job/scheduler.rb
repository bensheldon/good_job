require "concurrent/scheduled_task"
require "concurrent/executor/thread_pool_executor"
require "concurrent/utility/processor_counter"

module GoodJob
  class Scheduler
    MINIMUM_EXECUTION_INTERVAL = 0.1

    DEFAULT_TIMER_OPTIONS = {
      execution_interval: 1,
      timeout_interval: 1,
      run_now: true
    }.freeze

    MAX_THREADS = Concurrent.processor_count

    DEFAULT_POOL_OPTIONS = {
      name:            'good_job',
      min_threads:     0,
      max_threads:     MAX_THREADS,
      auto_terminate:  true,
      idletime:        0,
      max_queue:       0,
      fallback_policy:  :abort # shouldn't matter -- 0 max queue
    }.freeze

    def initialize(query = GoodJob::Job.all, **options)
      @query = query

      @active_jobs = Concurrent::Array.new
      @pool = Concurrent::ThreadPoolExecutor.new(DEFAULT_POOL_OPTIONS)
      @timer = Concurrent::TimerTask.new(DEFAULT_TIMER_OPTIONS) do
        schedule_jobs
        true
      end
      # @timer.add_observer(TaskObserver.new)
      @timer.execute
    end

    def active_jobs
      @active_jobs
    end

    def execute
    end

    def shutdown(wait: true)
      if @timer.running?
        @timer.shutdown
        @timer.wait_for_termination if wait
      end

      if @pool.running?
        @pool.shutdown
        @pool.wait_for_termination if wait
      end
    end

    def schedule_jobs(count = 100)
      idle_threads = @pool.max_length - @active_jobs.count
      to_enqueue = [count, idle_threads].min
      return if to_enqueue.zero?

      jobs = @query.advisory_unlocked.limit(to_enqueue).load
      puts "Scheduling #{jobs.size} job(s)"
      jobs.each { |job| schedule_job(job) }
    end

    def schedule_job(job)
      future = Concurrent::Future.new(args: [job], executor: @pool) do |j|
        Rails.application.executor.wrap do
          thread_name = Thread.current.name || Thread.current.object_id
          puts "Executing job #{job.id} in thread #{thread_name}"

          JobWrapper.new(j).perform

          true
        end
      end
      future.add_observer(TaskObserver.new(job, @active_jobs, self))
      future.execute
      @active_jobs << job
    end

    class TaskObserver
      def initialize(job, active_jobs, scheduler)
        @job = job
        @active_jobs = active_jobs
        @scheduler = scheduler
      end

      def update(time, result, ex)
        if result
          puts "(#{time}) Execution of #{@job.id} successfully returned #{result}\n"
        elsif ex.is_a?(Concurrent::TimeoutError)
          puts "(#{time}) Execution of #{@job.id} timed out\n"
        else
          puts "(#{time}) Execution of #{@job.id} failed with error #{result} #{ex}\n"
        end

        @active_jobs.delete(@job)
        @scheduler.schedule_jobs(1)
      end
    end
  end
end
