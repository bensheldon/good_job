module GoodJob # :nodoc:
  #
  # Schedulers are generic thread pools that are responsible for
  # periodically checking for available tasks, executing tasks within a thread,
  # and efficiently scaling active threads.
  #
  # Every scheduler has a single {Performer} that will execute tasks.
  # The scheduler is responsible for calling its performer efficiently across threads managed by an instance of +Concurrent::ThreadPoolExecutor+.
  # If a performer does not have work, the thread will go to sleep.
  # The scheduler maintains an instance of +Concurrent::TimerTask+, which wakes sleeping threads and causes them to check whether the performer has new work.
  #
  class Scheduler
    # Defaults for instance of Concurrent::ThreadPoolExecutor
    # The thread pool is where work is performed.
    DEFAULT_POOL_OPTIONS = {
      name: name,
      min_threads: 0,
      max_threads: Configuration::DEFAULT_MAX_THREADS,
      auto_terminate: true,
      idletime: 60,
      max_queue: 0,
      fallback_policy: :discard,
    }.freeze

    # @!attribute [r] instances
    #   @!scope class
    #   List of all instantiated Schedulers in the current process.
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

        GoodJob::Scheduler.new(job_performer, max_threads: max_threads)
      end

      if schedulers.size > 1
        GoodJob::MultiScheduler.new(schedulers)
      else
        schedulers.first
      end
    end

    # @param performer [GoodJob::Performer]
    # @param max_threads [Numeric, nil] number of seconds between polls for jobs
    def initialize(performer, max_threads: nil)
      raise ArgumentError, "Performer argument must implement #next" unless performer.respond_to?(:next)

      self.class.instances << self

      @performer = performer

      @pool_options = DEFAULT_POOL_OPTIONS.dup
      @pool_options[:max_threads] = max_threads if max_threads.present?
      @pool_options[:name] = "GoodJob::Scheduler(queues=#{@performer.name} max_threads=#{@pool_options[:max_threads]})"

      @scheduled_task_queue = ScheduledTaskQueue.new(max_size: @pool_options[:max_threads])

      create_pool
    end

    # Shut down the scheduler.
    # This stops all threads in the pool.
    # If +wait+ is +true+, the scheduler will wait for any active tasks to finish.
    # If +wait+ is +false+, this method will return immediately even though threads may still be running.
    # Use {#shutdown?} to determine whether threads have stopped.
    # @param wait [Boolean] Wait for actively executing jobs to finish
    # @return [void]
    def shutdown(wait: true)
      return unless @pool&.running?

      instrument("scheduler_shutdown_start", { wait: wait })
      instrument("scheduler_shutdown", { wait: wait }) do
        @pool.shutdown
        @pool.wait_for_termination if wait
        # TODO: Should be killed if wait is not true
      end
    end

    # Tests whether the scheduler is shutdown.
    # @return [true, false, nil]
    def shutdown?
      !@pool&.running?
    end

    # Restart the Scheduler.
    # When shutdown, start; or shutdown and start.
    # @param wait [Boolean] Wait for actively executing jobs to finish
    # @return [void]
    def restart(wait: true)
      instrument("scheduler_restart_pools") do
        shutdown(wait: wait) unless shutdown?
        create_pool
      end
    end

    # Wakes a thread to allow the performer to execute a task.
    # @param state [nil, Object] Contextual information for the performer. See {Performer#next?}.
    # @return [nil, Boolean] Whether work was started.
    #   Returns +nil+ if the scheduler is unable to take new work, for example if the thread pool is shut down or at capacity.
    #   Returns +true+ if the performer started executing work.
    #   Returns +false+ if the performer decides not to attempt to execute a task based on the +state+ that is passed to it.
    def create_thread(state = nil)
      return nil unless @pool.running?

      if state
        return false unless @performer.next?(state)

        if state[:scheduled_at]
          scheduled_at = if state[:scheduled_at].is_a? String
                           Time.zone.parse state[:scheduled_at]
                         else
                           state[:scheduled_at]
                         end
        end
      end

      if scheduled_at && scheduled_at > Time.current
        task = CustomConcurrent::ScheduledTask.new(scheduled_at, args: [@performer], executor: @pool) do |performer|
          output = nil
          Rails.application.executor.wrap { output = performer.next }
          output
        end

        if @scheduled_task_queue.push(task)
          task.add_observer(self, :task_observer)
          task.execute
        end

        true
      elsif @pool.ready_worker_count.positive?
        task = Concurrent::Future.new(args: [@performer], executor: @pool) do |performer|
          output = nil
          Rails.application.executor.wrap { output = performer.next }
          output
        end
        task.add_observer(self, :task_observer)
        task.execute

        true
      else
        nil
      end
    end

    # Invoked on completion of ThreadPoolExecutor task
    # @!visibility private
    # @return [void]
    def task_observer(time, output, thread_error)
      GoodJob.on_thread_error.call(thread_error) if thread_error && GoodJob.on_thread_error.respond_to?(:call)
      instrument("finished_job_task", { result: output, error: thread_error, time: time })

      if output
        create_thread
      elsif @performer.respond_to?(:next_at)
        @scheduled_task_queue.max_size - @scheduled_task_queue.size
        Array(@performer.next_at(
        @timer_wake.push(next_at) if next_at
      end
    end

    private

    def create_pool
      instrument("scheduler_create_pool", { performer_name: @performer.name, max_threads: @pool_options[:max_threads] }) do
        @pool = CustomConcurrent::ThreadPoolExecutor.new(@pool_options)
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
end
