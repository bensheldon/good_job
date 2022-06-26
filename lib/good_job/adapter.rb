# frozen_string_literal: true
module GoodJob
  #
  # ActiveJob Adapter.
  #
  class Adapter
    # @!attribute [r] instances
    #   @!scope class
    #   List of all instantiated Adapters in the current process.
    #   @return [Array<GoodJob::Adapter>, nil]
    cattr_reader :instances, default: [], instance_reader: false

    # @param execution_mode [Symbol, nil] specifies how and where jobs should be executed. You can also set this with the environment variable +GOOD_JOB_EXECUTION_MODE+.
    #
    #  - +:inline+ executes jobs immediately in whatever process queued them (usually the web server process). This should only be used in test and development environments.
    #  - +:external+ causes the adapter to enqueue jobs, but not execute them. When using this option (the default for production environments), you'll need to use the command-line tool to actually execute your jobs.
    #  - +:async+ (or +:async_server+) executes jobs in separate threads within the Rails web server process (`bundle exec rails server`). It can be more economical for small workloads because you don't need a separate machine or environment for running your jobs, but if your web server is under heavy load or your jobs require a lot of resources, you should choose +:external+ instead.
    #    When not in the Rails web server, jobs will execute in +:external+ mode to ensure jobs are not executed within `rails console`, `rails db:migrate`, `rails assets:prepare`, etc.
    #  - +:async_all+ executes jobs in any Rails process.
    #
    #  The default value depends on the Rails environment:
    #
    #  - +development+: +:async:+
    #   -+test+: +:inline+
    #  - +production+ and all other environments: +:external+
    #
    def initialize(execution_mode: nil)
      @configuration = GoodJob::Configuration.new({ execution_mode: execution_mode })
      @configuration.validate!
      self.class.instances << self

      start_async if GoodJob.async_ready?
    end

    # Enqueues the ActiveJob job to be performed.
    # For use by Rails; you should generally not call this directly.
    # @param active_job [ActiveJob::Base] the job to be enqueued from +#perform_later+
    # @return [GoodJob::Execution]
    def enqueue(active_job)
      enqueue_at(active_job, nil)
    end

    # Enqueues an ActiveJob job to be run at a specific time.
    # For use by Rails; you should generally not call this directly.
    # @param active_job [ActiveJob::Base] the job to be enqueued from +#perform_later+
    # @param timestamp [Integer, nil] the epoch time to perform the job
    # @return [GoodJob::Execution]
    def enqueue_at(active_job, timestamp)
      scheduled_at = timestamp ? Time.zone.at(timestamp) : nil
      will_execute_inline = execute_inline? && (scheduled_at.nil? || scheduled_at <= Time.current)

      execution = GoodJob::Execution.enqueue(
        active_job,
        scheduled_at: scheduled_at,
        create_with_advisory_lock: will_execute_inline
      )

      if will_execute_inline
        begin
          result = execution.perform
        ensure
          execution.advisory_unlock
        end
        raise result.unhandled_error if result.unhandled_error
      else
        job_state = { queue_name: execution.queue_name }
        job_state[:scheduled_at] = execution.scheduled_at if execution.scheduled_at

        executed_locally = execute_async? && @scheduler&.create_thread(job_state)
        Notifier.notify(job_state) unless executed_locally
      end

      execution
    end

    # Shut down the thread pool executors.
    # @param timeout [nil, Numeric, Symbol] Seconds to wait for active threads.
    #   * +nil+, the scheduler will trigger a shutdown but not wait for it to complete.
    #   * +-1+, the scheduler will wait until the shutdown is complete.
    #   * +0+, the scheduler will immediately shutdown and stop any threads.
    #   * A positive number will wait that many seconds before stopping any remaining active threads.
    # @return [void]
    def shutdown(timeout: :default)
      timeout = if timeout == :default
                  @configuration.shutdown_timeout
                else
                  timeout
                end

      executables = [@notifier, @poller, @scheduler].compact
      GoodJob._shutdown_all(executables, timeout: timeout)
      @_async_started = false
    end

    # Whether in +:async+ execution mode.
    # @return [Boolean]
    def execute_async?
      @configuration.execution_mode == :async_all ||
        (@configuration.execution_mode.in?([:async, :async_server]) && in_server_process?)
    end

    # Whether in +:external+ execution mode.
    # @return [Boolean]
    def execute_externally?
      @configuration.execution_mode == :external ||
        (@configuration.execution_mode.in?([:async, :async_server]) && !in_server_process?)
    end

    # Whether in +:inline+ execution mode.
    # @return [Boolean]
    def execute_inline?
      @configuration.execution_mode == :inline
    end

    # Start async executors
    # @return [void]
    def start_async
      return unless execute_async?

      @notifier = GoodJob::Notifier.new
      @poller = GoodJob::Poller.new(poll_interval: @configuration.poll_interval)
      @scheduler = GoodJob::Scheduler.from_configuration(@configuration, warm_cache_on_initialize: true)
      @notifier.recipients << [@scheduler, :create_thread]
      @poller.recipients << [@scheduler, :create_thread]

      @cron_manager = GoodJob::CronManager.new(@configuration.cron_entries, start_on_initialize: true) if @configuration.enable_cron?

      @_async_started = true
    end

    # Whether the async executors are running
    # @return [Boolean]
    def async_started?
      @_async_started
    end

    private

    # Whether running in a web server process.
    # @return [Boolean, nil]
    def in_server_process?
      return @_in_server_process if defined? @_in_server_process

      @_in_server_process = Rails.const_defined?(:Server) ||
                            caller.grep(%r{config.ru}).any? || # EXAMPLE: config.ru:3:in `block in <main>' OR config.ru:3:in `new_from_string'
                            caller.grep(%{/rack/handler/}).any? || # EXAMPLE: iodine-0.7.44/lib/rack/handler/iodine.rb:13:in `start'
                            (Concurrent.on_jruby? && caller.grep(%r{jruby/rack/rails_booter}).any?) # EXAMPLE: uri:classloader:/jruby/rack/rails_booter.rb:83:in `load_environment'
    end
  end
end
