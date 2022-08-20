# frozen_string_literal: true
module GoodJob
  class Manager
    cattr_reader :mutex, default: Mutex.new

    def initialize(configuration: GoodJob.configuration)
      @configuration = configuration
    end

    def create_thread(state)
      mutex.synchronize { restart unless @scheduler }
      @scheduler.create_thread(state)
    end

    def running?
      @scheduler&.running?
    end

    def restart
      shutdown

      @notifier = GoodJob::Notifier.new
      @poller = GoodJob::Poller.new(poll_interval: @configuration.poll_interval)
      @scheduler = GoodJob::Scheduler.from_configuration(@configuration, warm_cache_on_initialize: true)
      @notifier.recipients << [@scheduler, :create_thread]
      @poller.recipients << [@scheduler, :create_thread]

      @cron_manager = GoodJob::CronManager.new(@configuration.cron_entries, start_on_initialize: true) if @configuration.enable_cron?
    end

    def shutdown
      executors = [@notifier, @poller, @scheduler, @cron_manager].compact
      GoodJob._shutdown_all(executors, timeout: @configuration.shutdown_timeout)
    end
  end
end
