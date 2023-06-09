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
    cattr_reader :instances, default: [], instance_reader: false

    # @param configuration [GoodJob::Configuration] Configuration to use for this capsule.
    def initialize(configuration: GoodJob.configuration)
      self.class.instances << self
      @configuration = configuration

      @startable = true
      @running = false
      @mutex = Mutex.new
    end

    # Start the capsule once. After a shutdown, {#restart} must be used to start again.
    # @return [nil, Boolean] Whether the capsule was started.
    def start(force: false)
      return unless startable?(force: force)

      @mutex.synchronize do
        return unless startable?(force: force)

        @notifier = GoodJob::Notifier.new(enable_listening: @configuration.enable_listen_notify)
        @poller = GoodJob::Poller.new(poll_interval: @configuration.poll_interval)
        @scheduler = GoodJob::Scheduler.from_configuration(@configuration, warm_cache_on_initialize: true)
        @notifier.recipients << [@scheduler, :create_thread]
        @poller.recipients << [@scheduler, :create_thread]

        @cron_manager = GoodJob::CronManager.new(@configuration.cron_entries, start_on_initialize: true) if @configuration.enable_cron?

        @startable = false
        @running = true
      end
    end

    # Shut down the thread pool executors.
    # @param timeout [nil, Numeric, Symbol] Seconds to wait for active threads.
    #   * +-1+ will wait for all active threads to complete.
    #   * +0+ will interrupt active threads.
    #   * +N+ will wait at most N seconds and then interrupt active threads.
    #   * +nil+ will trigger a shutdown but not wait for it to complete.
    # @return [void]
    def shutdown(timeout: :default)
      timeout = timeout == :default ? @configuration.shutdown_timeout : timeout
      GoodJob._shutdown_all([@notifier, @poller, @scheduler, @cron_manager].compact, timeout: timeout)
      @startable = false
      @running = false
    end

    # Shutdown and then start the capsule again.
    # @param timeout [Numeric, Symbol] Seconds to wait for active threads.
    # @return [void]
    def restart(timeout: :default)
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

    private

    def startable?(force: false)
      !@running && (@startable || force)
    end
  end
end
