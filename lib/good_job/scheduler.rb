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

      @pool = Concurrent::ThreadPoolExecutor.new(DEFAULT_POOL_OPTIONS)
      @timer = Concurrent::TimerTask.new(DEFAULT_TIMER_OPTIONS) do
        idle_threads = @pool.max_length - @pool.length
        puts "There are idle_threads: #{idle_threads}"
        create_thread if idle_threads.positive?
        true
      end
      @timer.execute
    end

    def ordered_query
      @query.where("scheduled_at < ?", Time.current).or(@query.where(scheduled_at: nil)).order(priority: :desc)
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

    def create_thread
      future = Concurrent::Future.new(args: [ordered_query], executor: @pool) do |query|
        Rails.application.executor.wrap do
          thread_name = Thread.current.name || Thread.current.object_id
          while job = query.with_advisory_lock.first
            puts "Executing job #{job.id} in thread #{thread_name}"

            JobWrapper.new(job).perform

            job.advisory_unlock
          end
          true
        end
      end
      future.add_observer(TaskObserver.new(self))
      future.execute
    end

    class TaskObserver
      def initialize(scheduler)
        @scheduler = scheduler
      end

      def update(time, result, ex)
        if result
          puts "(#{time}) Execution successfully returned #{result}\n"
        elsif ex.is_a?(Concurrent::TimeoutError)
          puts "(#{time}) Execution timed out\n"
        else
          puts "(#{time}) Execution failed with error #{result} #{ex}\n"
        end
      end
    end
  end
end
