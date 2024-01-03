# frozen_string_literal: true

module GoodJob
  # Delegates the interface of a single {Scheduler} to multiple Schedulers.
  class MultiScheduler
    # Creates MultiScheduler from a GoodJob::Configuration instance.
    # @param configuration [GoodJob::Configuration]
    # @param warm_cache_on_initialize [Boolean]
    # @return [GoodJob::MultiScheduler]
    def self.from_configuration(configuration, warm_cache_on_initialize: false)
      schedulers = configuration.queue_string.split(';').map do |queue_string_and_max_threads|
        queue_string, max_threads = queue_string_and_max_threads.split(':')
        max_threads = (max_threads || configuration.max_threads).to_i

        job_performer = GoodJob::JobPerformer.new(queue_string)
        GoodJob::Scheduler.new(
          job_performer,
          max_threads: max_threads,
          max_cache: configuration.max_cache,
          warm_cache_on_initialize: warm_cache_on_initialize,
          cleanup_interval_seconds: configuration.cleanup_interval_seconds,
          cleanup_interval_jobs: configuration.cleanup_interval_jobs
        )
      end

      new(schedulers)
    end

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
        check_queue_at: scheduler_stats.map { |stats| stats.fetch(:check_queue_at, nil) }.compact.max,
      }
    end
  end
end
