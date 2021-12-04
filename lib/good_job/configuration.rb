# frozen_string_literal: true
module GoodJob
  #
  # +GoodJob::Configuration+ provides normalized configuration information to
  # the rest of GoodJob. It combines environment information with explicitly
  # set options to get the final values for each option.
  #
  class Configuration
    # Valid execution modes.
    EXECUTION_MODES = [:async, :async_all, :async_server, :external, :inline].freeze
    # Default number of threads to use per {Scheduler}
    DEFAULT_MAX_THREADS = 5
    # Default number of seconds between polls for jobs
    DEFAULT_POLL_INTERVAL = 10
    # Default poll interval for async in development environment
    DEFAULT_DEVELOPMENT_ASYNC_POLL_INTERVAL = -1
    # Default number of threads to use per {Scheduler}
    DEFAULT_MAX_CACHE = 10000
    # Default number of seconds to preserve jobs for {CLI#cleanup_preserved_jobs} and {GoodJob.cleanup_preserved_jobs}
    DEFAULT_CLEANUP_PRESERVED_JOBS_BEFORE_SECONDS_AGO = 24 * 60 * 60
    # Default number of jobs to execute between preserved job cleanup runs
    DEFAULT_CLEANUP_INTERVAL_JOBS = nil
    # Default number of seconds to wait between preserved job cleanup runs
    DEFAULT_CLEANUP_INTERVAL_SECONDS = nil
    # Default to always wait for jobs to finish for {Adapter#shutdown}
    DEFAULT_SHUTDOWN_TIMEOUT = -1
    # Default to not running cron
    DEFAULT_ENABLE_CRON = false

    # The options that were explicitly set when initializing +Configuration+.
    # @return [Hash]
    attr_reader :options

    # The environment from which to read GoodJob's environment variables. By
    # default, this is the current process's environment, but it can be set
    # to something else in {#initialize}.
    # @return [Hash]
    attr_reader :env

    # @param options [Hash] Any explicitly specified configuration options to
    #   use. Keys are symbols that match the various methods on this class.
    # @param env [Hash] A +Hash+ from which to read environment variables that
    #   might specify additional configuration values.
    def initialize(options, env: ENV)
      @options = options
      @env = env
    end

    def validate!
      raise ArgumentError, "GoodJob execution mode must be one of #{EXECUTION_MODES.join(', ')}. It was '#{execution_mode}' which is not valid." unless execution_mode.in?(EXECUTION_MODES)
    end

    # Specifies how and where jobs should be executed. See {Adapter#initialize}
    # for more details on possible values.
    # @return [Symbol]
    def execution_mode
      mode = if GoodJob::CLI.within_exe?
               :external
             else
               options[:execution_mode] ||
                 rails_config[:execution_mode] ||
                 env['GOOD_JOB_EXECUTION_MODE']
             end

      if mode
        mode.to_sym
      elsif Rails.env.development?
        :async
      elsif Rails.env.test?
        :inline
      else
        :external
      end
    end

    # Indicates the number of threads to use per {Scheduler}. Note that
    # {#queue_string} may provide more specific thread counts to use with
    # individual schedulers.
    # @return [Integer]
    def max_threads
      (
        options[:max_threads] ||
          rails_config[:max_threads] ||
          env['GOOD_JOB_MAX_THREADS'] ||
          env['RAILS_MAX_THREADS'] ||
          DEFAULT_MAX_THREADS
      ).to_i
    end

    # Describes which queues to execute jobs from and how those queues should
    # be grouped into {Scheduler} instances. See
    # {file:README.md#optimize-queues-threads-and-processes} for more details
    # on the format of this string.
    # @return [String]
    def queue_string
      options[:queues].presence ||
        rails_config[:queues].presence ||
        env['GOOD_JOB_QUEUES'].presence ||
        '*'
    end

    # The number of seconds between polls for jobs. GoodJob will execute jobs
    # on queues continuously until a queue is empty, at which point it will
    # poll (using this interval) for new queued jobs to execute.
    # @return [Integer]
    def poll_interval
      interval = (
        options[:poll_interval] ||
          rails_config[:poll_interval] ||
          env['GOOD_JOB_POLL_INTERVAL']
      )

      if interval
        interval.to_i
      elsif Rails.env.development? && execution_mode.in?([:async, :async_all, :async_server])
        DEFAULT_DEVELOPMENT_ASYNC_POLL_INTERVAL
      else
        DEFAULT_POLL_INTERVAL
      end
    end

    # The maximum number of future-scheduled jobs to store in memory.
    # Storing future-scheduled jobs in memory reduces execution latency
    # at the cost of increased memory usage. 10,000 stored jobs = ~20MB.
    # @return [Integer]
    def max_cache
      (
        options[:max_cache] ||
          rails_config[:max_cache] ||
          env['GOOD_JOB_MAX_CACHE'] ||
          DEFAULT_MAX_CACHE
      ).to_i
    end

    # The number of seconds to wait for jobs to finish when shutting down
    # before stopping the thread. +-1+ is forever.
    # @return [Numeric]
    def shutdown_timeout
      (
        options[:shutdown_timeout] ||
          rails_config[:shutdown_timeout] ||
          env['GOOD_JOB_SHUTDOWN_TIMEOUT'] ||
          DEFAULT_SHUTDOWN_TIMEOUT
      ).to_f
    end

    # Whether to run cron
    # @return [Boolean]
    def enable_cron
      value = ActiveModel::Type::Boolean.new.cast(
        options[:enable_cron] ||
          rails_config[:enable_cron] ||
          env['GOOD_JOB_ENABLE_CRON'] ||
          false
      )
      value && cron.size.positive?
    end

    alias enable_cron? enable_cron

    def cron
      env_cron = JSON.parse(ENV['GOOD_JOB_CRON'], symbolize_names: true) if ENV['GOOD_JOB_CRON'].present?

      options[:cron] ||
        rails_config[:cron] ||
        env_cron ||
        {}
    end

    def cron_entries
      cron.map { |cron_key, params| GoodJob::CronEntry.new(params.merge(key: cron_key)) }
    end

    # Number of seconds to preserve jobs when using the +good_job cleanup_preserved_jobs+ CLI command.
    # This configuration is only used when {GoodJob.preserve_job_records} is +true+.
    # @return [Integer]
    def cleanup_preserved_jobs_before_seconds_ago
      (
        options[:before_seconds_ago] ||
          rails_config[:cleanup_preserved_jobs_before_seconds_ago] ||
          env['GOOD_JOB_CLEANUP_PRESERVED_JOBS_BEFORE_SECONDS_AGO'] ||
          DEFAULT_CLEANUP_PRESERVED_JOBS_BEFORE_SECONDS_AGO
      ).to_i
    end

    # Number of jobs a {Scheduler} will execute before cleaning up preserved jobs.
    # @return [Integer, nil]
    def cleanup_interval_jobs
      value = (
        rails_config[:cleanup_interval_jobs] ||
          env['GOOD_JOB_CLEANUP_INTERVAL_JOBS'] ||
          DEFAULT_CLEANUP_INTERVAL_JOBS
      )
      value.present? ? value.to_i : nil
    end

    # Number of seconds a {Scheduler} will wait before cleaning up preserved jobs.
    # @return [Integer, nil]
    def cleanup_interval_seconds
      value = (
        rails_config[:cleanup_interval_seconds] ||
          env['GOOD_JOB_CLEANUP_INTERVAL_SECONDS'] ||
          DEFAULT_CLEANUP_INTERVAL_SECONDS
      )
      value.present? ? value.to_i : nil
    end

    # Tests whether to daemonize the process.
    # @return [Boolean]
    def daemonize?
      options[:daemonize] || false
    end

    # Path of the pidfile to create when running as a daemon.
    # @return [Pathname,String]
    def pidfile
      options[:pidfile] ||
        env['GOOD_JOB_PIDFILE'] ||
        Rails.application.root.join('tmp', 'pids', 'good_job.pid')
    end

    # Port of the probe server
    # @return [nil,Integer]
    def probe_port
      options[:probe_port] ||
        env['GOOD_JOB_PROBE_PORT']
    end

    private

    def rails_config
      Rails.application.config.good_job
    end
  end
end
