# frozen_string_literal: true

module GoodJob
  # A GoodJob::Capsule contains the resources necessary to execute jobs, including
  # a {GoodJob::Scheduler}, {GoodJob::Poller}, {GoodJob::Notifier}, and {GoodJob::CronManager}.
  # GoodJob creates a default capsule on initialization.
  class Capsule
    # @!attribute [r] instances
    #   @!scope class
    #   List of all instantiated Capsules in the current process.
    #   @return [Array<GoodJob::Capsule>, nil]
    cattr_reader :instances, default: Concurrent::Array.new, instance_reader: false

    attr_reader :tracker

    # @param configuration [GoodJob::Configuration] Configuration to use for this capsule.
    def initialize(configuration: GoodJob.configuration)
      @configuration = configuration
      @startable = true
      @running = false
      @mutex = Mutex.new

      # TODO: allow the shared executor to remain until the very, very end, then shutdown. And allow restart.
      @shared_executor = GoodJob::SharedExecutor.new
      @tracker = GoodJob::CapsuleTracker.new

      self.class.instances << self
    end

    # Start the capsule once. After a shutdown, {#restart} must be used to start again.
    # @return [nil, Boolean] Whether the capsule was started.
    def start(force: false)
      return unless startable?(force: force)

      @mutex.synchronize do
        return unless startable?(force: force)

        @notifier = GoodJob::Notifier.new(enable_listening: @configuration.enable_listen_notify, capsule: self, executor: @shared_executor.executor)
        @poller = GoodJob::Poller.new(poll_interval: @configuration.poll_interval)
        @scheduler = GoodJob::Scheduler.from_configuration(@configuration, capsule: self, warm_cache_on_initialize: true)
        @notifier.recipients << [@scheduler, :create_thread]
        @poller.recipients << [@scheduler, :create_thread]

        @cron_manager = GoodJob::CronManager.new(@configuration.cron_entries, start_on_initialize: true, executor: @shared_executor.executor) if @configuration.enable_cron?

        @tracker.register
        @startable = false
        @running = true
      end
    end

    # Shut down the thread pool executors.
    # @param timeout [nil, Numeric, GoodJob::DEFAULT_SHUTDOWN_TIMEOUT] Seconds to wait for active threads.
    #   * +-1+ will wait for all active threads to complete.
    #   * +0+ will interrupt active threads.
    #   * +N+ will wait at most N seconds and then interrupt active threads.
    #   * +nil+ will trigger a shutdown but not wait for it to complete.
    # @return [void]
    def shutdown(timeout: GoodJob::USE_GLOBAL_SHUTDOWN_TIMEOUT)
      @mutex.synchronize do
        timeout = @configuration.shutdown_timeout if timeout == GoodJob::USE_GLOBAL_SHUTDOWN_TIMEOUT
        GoodJob._shutdown_all([@notifier, @poller, @scheduler, @cron_manager].compact, timeout: timeout)

        @tracker.unregister
        @startable = false
        @running = false
      end
    end

    # Shutdown and then start the capsule again.
    # @param timeout [Numeric, Symbol] Seconds to wait for active threads.
    # @return [void]
    def restart(timeout: GoodJob::USE_GLOBAL_SHUTDOWN_TIMEOUT)
      raise ArgumentError, "Capsule#restart cannot be called with a timeout of nil" if timeout.nil?

      shutdown(timeout: timeout)
      start(force: true)
    end

    # @return [Boolean] Whether the capsule is currently running.
    def running?
      @running
    end

    # @return [Boolean] Whether the capsule has been shutdown.
    def shutdown?
      [@notifier, @poller, @scheduler, @cron_manager].compact.all?(&:shutdown?)
    end

    # Creates an execution thread(s) with the given attributes.
    # @param job_state [Hash, nil] See {GoodJob::Scheduler#create_thread}.
    # @return [Boolean, nil] Whether the thread was created.
    def create_thread(job_state = nil)
      start if startable?
      @scheduler&.create_thread(job_state)
    end

    # UUID for this capsule; to be used for inspection (not directly for locking jobs).
    # @return [String]
    def process_id
      @tracker.process_id
    end

    private

    def startable?(force: false)
      !@running && (@startable || force)
    end
  end
end
