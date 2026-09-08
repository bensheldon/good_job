# frozen_string_literal: true

module GoodJob
  # Delegates the interface of a single {Scheduler} to multiple Schedulers.
  class MultiScheduler
    # Creates MultiScheduler from a GoodJob::Configuration instance.
    # @param configuration [GoodJob::Configuration]
    # @param warm_cache_on_initialize [Boolean]
    # @return [GoodJob::MultiScheduler]
    def self.from_configuration(configuration, capsule: GoodJob.capsule, warm_cache_on_initialize: false)
      queue_configurations = configuration.queue_string.split(';').map(&:strip).map do |queue_string_and_count|
        queue_string_and_count.split(':').map { |str| str.strip.presence }
      end

      fibers_fallback = false
      begin
        fibers = configuration.fibers

        if fibers
          queue_configurations.each do |queue_string, queue_count|
            next unless queue_count

            count = Integer(queue_count, 10, exception: false)
            raise ArgumentError, "GoodJob queue pool size must be a positive integer, but was '#{queue_count}' for queue '#{queue_string}'" unless count&.positive?
          end
          Scheduler.validate_fiber_execution!

          GoodJob.logger.warn("GoodJob: `fibers` (#{fibers}) overrides `max_threads` (#{configuration.max_threads}) for each scheduler.") if configuration.max_threads_configured?
          GoodJob.logger.warn("GoodJob: :advisory holds one database connection per running job. Use `lock_strategy = :skiplocked` with the `good_jobs.lock_type` migration to allow connection sharing. Transactions and permanent leases still hold connections.") if configuration.lock_strategy == :advisory
          GoodJob.logger.warn("GoodJob: `lower_thread_priority` is ignored because job fibers share one reactor thread.") if configuration.lower_thread_priority
          warn_downgraded_lock_strategy(configuration)
        end
      rescue ArgumentError => e
        # Web and worker processes may share GOOD_JOB_FIBERS despite different Rails settings.
        raise if GoodJob.cli?

        GoodJob.logger.error("GoodJob: ignoring `fibers` and using a thread pool for this #{configuration.execution_mode} process: #{e.message}")
        fibers = nil
        fibers_fallback = true
      end

      schedulers = queue_configurations.map do |queue_string, queue_count|
        scheduler_options = {
          max_cache: configuration.max_cache,
          warm_cache_on_initialize: warm_cache_on_initialize,
          cleanup_interval_seconds: configuration.cleanup_interval_seconds,
          cleanup_interval_jobs: configuration.cleanup_interval_jobs,
          lower_thread_priority: configuration.lower_thread_priority,
        }

        if fibers
          fiber_count = queue_count ? Integer(queue_count, 10) : fibers
          GoodJob.logger.warn("GoodJob: queue '#{queue_string}' uses #{fiber_count} fibers, overriding `fibers` (#{fibers}).") if fiber_count != fibers
          scheduler_options[:fibers] = fiber_count
        else
          # Fiber counts can be too large for thread pools; preserve smaller queue limits.
          thread_count = (queue_count || configuration.max_threads).to_i
          thread_count = [thread_count, configuration.max_threads].min if fibers_fallback
          scheduler_options[:max_threads] = thread_count
        end

        job_performer = GoodJob::JobPerformer.new(queue_string, capsule: capsule)
        GoodJob::Scheduler.new(job_performer, **scheduler_options)
      end

      new(schedulers)
    end

    # Warn when a missing migration forces advisory locks and limits connection sharing.
    # @param configuration [GoodJob::Configuration]
    # @return [void]
    def self.warn_downgraded_lock_strategy(configuration)
      configured = configuration.lock_strategy
      effective = GoodJob::Job.effective_lock_strategy(configured)
      return if effective == configured

      GoodJob.logger.warn(
        "GoodJob: the #{configured.inspect} lock strategy is unavailable and has been downgraded to #{effective.inspect}, " \
        "which holds one database connection per running job. " \
        "Run `bin/rails generate good_job:update` and migrate to add `good_jobs.lock_type`."
      )
    rescue StandardError => e
      GoodJob.logger.debug { "GoodJob: could not verify the effective lock strategy: #{e.message}" }
    end
    private_class_method :warn_downgraded_lock_strategy

    # @return [Array<Scheduler>] List of the scheduler delegates
    attr_reader :schedulers

    # @param schedulers [Array<Scheduler>]
    def initialize(schedulers)
      @schedulers = schedulers
    end

    # Delegates to {Scheduler#running?}.
    # @return [Boolean, nil]
    def running?
      schedulers.all?(&:running?)
    end

    # Delegates to {Scheduler#shutdown?}.
    # @return [Boolean, nil]
    def shutdown?
      schedulers.all?(&:shutdown?)
    end

    # Delegates to {Scheduler#shutdown}.
    # @param timeout [Numeric, nil]
    # @return [void]
    def shutdown(timeout: -1)
      GoodJob._shutdown_all(schedulers, timeout: timeout)
    end

    # Delegates to {Scheduler#restart}.
    # @param timeout [Numeric, nil]
    # @return [void]
    def restart(timeout: -1)
      GoodJob._shutdown_all(schedulers, :restart, timeout: timeout)
    end

    # Delegates to {Scheduler#create_thread}.
    # @param state [Hash]
    # @return [Boolean, nil]
    def create_thread(state = nil)
      results = []

      if state && !state[:fanout]
        schedulers.any? do |scheduler|
          scheduler.create_thread(state).tap { |result| results << result }
        end
      else
        schedulers.each do |scheduler|
          results << scheduler.create_thread(state)
        end
      end

      if results.any?
        true
      elsif results.any?(false)
        false
      else # rubocop:disable Style/EmptyElse
        nil
      end
    end

    def lower_thread_priority=(value)
      schedulers.each do |scheduler|
        scheduler.lower_thread_priority = value
      end
    end

    def stats
      scheduler_stats = schedulers.map(&:stats)

      {
        schedulers: scheduler_stats,
        empty_executions_count: scheduler_stats.sum { |stats| stats.fetch(:empty_executions_count, 0) },
        errored_executions_count: scheduler_stats.sum { |stats| stats.fetch(:errored_executions_count, 0) },
        succeeded_executions_count: scheduler_stats.sum { |stats| stats.fetch(:succeeded_executions_count, 0) },
        total_executions_count: scheduler_stats.sum { |stats| stats.fetch(:total_executions_count, 0) },
        execution_at: scheduler_stats.map { |stats| stats.fetch(:execution_at, nil) }.compact.max,
        active_execution_thread_count: scheduler_stats.sum { |stats| stats.fetch(:active_threads, 0) },
        active_execution_count: scheduler_stats.sum { |stats| stats.fetch(:active_fibers, stats.fetch(:active_threads, 0)) },
        check_queue_at: scheduler_stats.map { |stats| stats.fetch(:check_queue_at, nil) }.compact.max,
      }
    end
  end
end
