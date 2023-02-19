# frozen_string_literal: true
module GoodJob
  class Capsule
    # @!attribute [r] instances
    #   @!scope class
    #   List of all instantiated Capsules in the current process.
    #   @return [Array<GoodJob::Capsule>, nil]
    cattr_reader :instances, default: [], instance_reader: false

    def initialize(configuration: GoodJob.configuration)
      self.class.instances << self
      @configuration = configuration
      @running = false
    end

    def start
      @process_manager = GoodJob::ProcessManager.new
      @notifier = GoodJob::Notifier.new(enable_listening: @configuration.enable_listen_notify)
      @poller = GoodJob::Poller.new(poll_interval: @configuration.poll_interval)
      @scheduler = GoodJob::Scheduler.from_configuration(@configuration, warm_cache_on_initialize: true)
      @notifier.recipients << [@scheduler, :create_thread]
      @poller.recipients << [@scheduler, :create_thread]

      @cron_manager = GoodJob::CronManager.new(@configuration.cron_entries, start_on_initialize: true) if @configuration.enable_cron?

      @process_manager.heartbeat # trigger once more to pick up all the schedulers
      @running = true
    end

    # Shut down the thread pool executors.
    # @param timeout [nil, Numeric, Symbol] Seconds to wait for active threads.
    #   * +nil+, the scheduler will trigger a shutdown but not wait for it to complete.
    #   * +-1+, the scheduler will wait until the shutdown is complete.
    #   * +0+, the scheduler will immediately shutdown and stop any threads.
    #   * A positive number will wait that many seconds before stopping any remaining active threads.
    # @return [void]
    def shutdown(timeout: :default)
      timeout = timeout == :default ? @configuration.shutdown_timeout : timeout
      GoodJob._shutdown_all([@notifier, @poller, @scheduler, @cron_manager].compact, timeout: timeout)
      @process_manager&.shutdown
      @running = false
    end

    def restart(timeout: :default)
      shutdown(timeout: timeout)
      start
    end

    def running?
      @running
    end

    def shutdown?
      [@notifier, @poller, @scheduler, @cron_manager].compact.all?(&:shutdown?) && (@process_manager ? @process_manager.shutdown? : true)
    end

    def execute(job_state)
      @scheduler&.create_thread(job_state) if @running
    end
  end
end
