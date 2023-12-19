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

    # @param configuration [GoodJob::Configuration] Configuration to use for this capsule.
    def initialize(configuration: GoodJob.configuration)
      @configuration = configuration
      @startable = true
      @started_at = nil
      @mutex = Mutex.new

      self.class.instances << self
    end

    # Start the capsule once. After a shutdown, {#restart} must be used to start again.
    # @return [nil, Boolean] Whether the capsule was started.
    def start(force: false)
      return unless startable?(force: force)

      @mutex.synchronize do
        return unless startable?(force: force)

        @shared_executor = GoodJob::SharedExecutor.new
        @notifier = GoodJob::Notifier.new(enable_listening: @configuration.enable_listen_notify, executor: @shared_executor.executor)
        @poller = GoodJob::Poller.new(poll_interval: @configuration.poll_interval)
        @multi_scheduler = GoodJob::MultiScheduler.from_configuration(@configuration, warm_cache_on_initialize: true)
        @notifier.recipients.push([@multi_scheduler, :create_thread])
        @poller.recipients.push(-> { @multi_scheduler.create_thread({ fanout: true }) })

        @cron_manager = GoodJob::CronManager.new(@configuration.cron_entries, start_on_initialize: true, executor: @shared_executor.executor) if @configuration.enable_cron?

        @startable = false
        @started_at = Time.current
      end
    end

    # Shut down the thread pool executors.
    # @param timeout [nil, Numeric, NONE] Seconds to wait for active threads.
    #   * +-1+ will wait for all active threads to complete.
    #   * +0+ will interrupt active threads.
    #   * +N+ will wait at most N seconds and then interrupt active threads.
    #   * +nil+ will trigger a shutdown but not wait for it to complete.
    # @return [void]
    def shutdown(timeout: NONE)
      timeout = @configuration.shutdown_timeout if timeout == NONE
      GoodJob._shutdown_all([@shared_executor, @notifier, @poller, @multi_scheduler, @cron_manager].compact, timeout: timeout)
      @startable = false
      @started_at = nil
    end

    # Shutdown and then start the capsule again.
    # @param timeout [Numeric, NONE] Seconds to wait for active threads.
    # @return [void]
    def restart(timeout: NONE)
      raise ArgumentError, "Capsule#restart cannot be called with a timeout of nil" if timeout.nil?

      shutdown(timeout: timeout)
      start(force: true)
    end

    # @return [Boolean] Whether the capsule is currently running.
    def running?
      @started_at.present?
    end

    # @return [Boolean] Whether the capsule has been shutdown.
    def shutdown?
      [@shared_executor, @notifier, @poller, @multi_scheduler, @cron_manager].compact.all?(&:shutdown?)
    end

    # @param duration [nil, Numeric] Length of idleness to check for (in seconds).
    # @return [Boolean] Whether the capsule is idle
    def idle?(duration = nil)
      scheduler_stats = @multi_scheduler&.stats || {}
      is_idle = scheduler_stats.fetch(:active_execution_thread_count, 0).zero?

      if is_idle && duration
        active_at = scheduler_stats.fetch(:execution_at, nil) || @started_at
        active_at.nil? || (Time.current - active_at >= duration)
      else
        is_idle
      end
    end

    # Creates an execution thread(s) with the given attributes.
    # @param job_state [Hash, nil] See {GoodJob::Scheduler#create_thread}.
    # @return [Boolean, nil] Whether the thread was created.
    def create_thread(job_state = nil)
      start if startable?
      @multi_scheduler&.create_thread(job_state)
    end

    private

    def startable?(force: false)
      !@started_at && (@startable || force)
    end
  end
end
