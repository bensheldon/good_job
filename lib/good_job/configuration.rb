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
    DEFAULT_MAX_CACHE = 10_000
    # Default number of seconds to preserve jobs for {CLI#cleanup_preserved_jobs} and {GoodJob.cleanup_preserved_jobs}
    DEFAULT_CLEANUP_PRESERVED_JOBS_BEFORE_SECONDS_AGO = 14.days.to_i
    # Default number of jobs to execute between preserved job cleanup runs
    DEFAULT_CLEANUP_INTERVAL_JOBS = 1_000
    # Default number of seconds to wait between preserved job cleanup runs
    DEFAULT_CLEANUP_INTERVAL_SECONDS = 10.minutes.to_i
    # Default to always wait for jobs to finish for {Adapter#shutdown}
    DEFAULT_SHUTDOWN_TIMEOUT = -1
    # Default to not running cron
    DEFAULT_ENABLE_CRON = false
    # Default to enabling LISTEN/NOTIFY
    DEFAULT_ENABLE_LISTEN_NOTIFY = true
    # Default Dashboard I18n locale
    DEFAULT_DASHBOARD_DEFAULT_LOCALE = :en

    def self.validate_execution_mode(execution_mode)
      raise ArgumentError, "GoodJob execution mode must be one of #{EXECUTION_MODES.join(', ')}. It was '#{execution_mode}' which is not valid." unless execution_mode.in?(EXECUTION_MODES)
    end

    # The options that were explicitly set when initializing +Configuration+.
    # It is safe to modify this hash in place; be sure to symbolize keys.
    # @return [Hash]
    attr_reader :options

    # The environment from which to read GoodJob's environment variables. By
    # default, this is the current process's environment, but it can be set
    # to something else in {#initialize}.
    # @return [Hash]
    attr_reader :env

    # Returns the maximum number of threads GoodJob might consume
    # @param warn [Boolean] whether to print a warning when over the limit
    # @return [Integer]
    def self.total_estimated_threads(warn: false)
      utility_threads = GoodJob::SharedExecutor::MAX_THREADS
      scheduler_threads = GoodJob::Scheduler.instances.sum { |scheduler| scheduler.stats[:max_threads] }

      good_job_threads = utility_threads + scheduler_threads
      puma_threads = (Puma::Server.current&.max_threads if defined?(Puma::Server)) || 0

      total_threads = good_job_threads + puma_threads
      activerecord_pool_size = ActiveRecord::Base.connection_pool&.size

      if warn && activerecord_pool_size && total_threads > activerecord_pool_size
        message = "GoodJob is using #{good_job_threads} threads, " \
                  "#{" and Puma is using #{puma_threads} threads, " if puma_threads.positive?}" \
                  "which is #{total_threads - activerecord_pool_size} thread(s) more than ActiveRecord's database connection pool size of #{activerecord_pool_size}. " \
                  "Consider increasing ActiveRecord's database connection pool size in config/database.yml."

        GoodJob.logger.warn message
      end

      good_job_threads
    end

    # @param options [Hash] Any explicitly specified configuration options to
    #   use. Keys are symbols that match the various methods on this class.
    # @param env [Hash] A +Hash+ from which to read environment variables that
    #   might specify additional configuration values.
    def initialize(options, env: ENV)
      @options = options
      @env = env

      @_in_webserver = nil
    end

    def validate!
      self.class.validate_execution_mode(execution_mode)
    end

    # Specifies how and where jobs should be executed. See {Adapter#initialize}
    # for more details on possible values.
    # @return [Symbol]
    def execution_mode
      mode = options[:execution_mode] ||
             rails_config[:execution_mode] ||
             env['GOOD_JOB_EXECUTION_MODE']
      mode = mode.to_sym if mode

      if mode
        if GoodJob::CLI.within_exe? && [:async, :async_server].include?(mode)
          :external
        else
          mode
        end
      elsif GoodJob::CLI.within_exe?
        :external
      elsif Rails.env.development?
        :async
      elsif Rails.env.test?
        :inline
      else # rubocop:disable Lint/DuplicateBranch
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

    def inline_execution_respects_schedule?
      !!rails_config[:inline_execution_respects_schedule]
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
    # @return [Float]
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
      env_cron = JSON.parse(ENV.fetch('GOOD_JOB_CRON'), symbolize_names: true) if ENV['GOOD_JOB_CRON'].present?

      options[:cron] ||
        rails_config[:cron] ||
        env_cron ||
        {}
    end

    def cron_entries
      cron.map { |cron_key, params| GoodJob::CronEntry.new(params.merge(key: cron_key)) }
    end

    # The number of queued jobs to select when polling for a job to run.
    # This limit is intended to avoid locking a large number of rows when selecting eligible jobs
    # from the queue. This value should be higher than the total number of threads across all good_job
    # processes to ensure a thread can retrieve an eligible and unlocked job.
    # @return [Integer, nil]
    def queue_select_limit
      (
        options[:queue_select_limit] ||
        rails_config[:queue_select_limit] ||
        env['GOOD_JOB_QUEUE_SELECT_LIMIT']
      )&.to_i
    end

    # The number of seconds that a good_job process will idle with out running a job before exiting
    # @return [Integer, nil] Number of seconds or nil means do not idle out.
    def idle_timeout
      (
        options[:idle_timeout] ||
        rails_config[:idle_timeout] ||
        env['GOOD_JOB_IDLE_TIMEOUT']
      )&.to_i || nil
    end

    # Whether to automatically destroy discarded jobs that have been preserved.
    # @return [Boolean]
    def cleanup_discarded_jobs?
      return rails_config[:cleanup_discarded_jobs] unless rails_config[:cleanup_discarded_jobs].nil?
      return ActiveModel::Type::Boolean.new.cast(env['GOOD_JOB_CLEANUP_DISCARDED_JOBS']) unless env['GOOD_JOB_CLEANUP_DISCARDED_JOBS'].nil?

      true
    end

    # Number of seconds to preserve jobs before automatic destruction.
    # @return [Integer]
    def cleanup_preserved_jobs_before_seconds_ago
      (
        options[:before_seconds_ago] ||
          rails_config[:cleanup_preserved_jobs_before_seconds_ago] ||
          env['GOOD_JOB_CLEANUP_PRESERVED_JOBS_BEFORE_SECONDS_AGO'] ||
          DEFAULT_CLEANUP_PRESERVED_JOBS_BEFORE_SECONDS_AGO
      ).to_i
    end

    # Number of jobs a {Scheduler} will execute before automatically cleaning up preserved jobs.
    # Positive values will clean up after that many jobs have run, false or 0 will disable, and -1 will clean up after every job.
    # @return [Integer, Boolean, nil]
    def cleanup_interval_jobs
      if rails_config.key?(:cleanup_interval_jobs)
        value = rails_config[:cleanup_interval_jobs]
        if value.nil?
          GoodJob.deprecator.warn(
            %(Setting `config.good_job.cleanup_interval_jobs` to `nil` will no longer disable count-based cleanups in GoodJob v4. Set to `false` to disable, or `-1` to run every time.)
          )
          value = false
        elsif value == 0 # rubocop:disable Style/NumericPredicate
          GoodJob.deprecator.warn(
            %(Setting `config.good_job.cleanup_interval_jobs` to `0` will disable count-based cleanups in GoodJob v4. Set to `false` to disable, or `-1` to run every time.)
          )
          value = -1
        end
      elsif env.key?('GOOD_JOB_CLEANUP_INTERVAL_JOBS')
        value = env['GOOD_JOB_CLEANUP_INTERVAL_JOBS']
        if value.blank?
          GoodJob.deprecator.warn(
            %(Setting `GOOD_JOB_CLEANUP_INTERVAL_JOBS` to `""` will no longer disable count-based cleanups in GoodJob v4. Set to `0` to disable, or `-1` to run every time.)
          )
          value = false
        elsif value == '0'
          value = false
        end
      else
        value = DEFAULT_CLEANUP_INTERVAL_JOBS
      end

      value ? value.to_i : false
    end

    # Number of seconds a {Scheduler} will wait before automatically cleaning up preserved jobs.
    # Positive values will clean up after that many jobs have run, false or 0 will disable, and -1 will clean up after every job.
    # @return [Integer, nil]
    def cleanup_interval_seconds
      if rails_config.key?(:cleanup_interval_seconds)
        value = rails_config[:cleanup_interval_seconds]

        if value.nil?
          GoodJob.deprecator.warn(
            %(Setting `config.good_job.cleanup_interval_seconds` to `nil` will no longer disable time-based cleanups in GoodJob v4. Set to `false` to disable, or `-1` to run every time.)
          )
          value = false
        elsif value == 0 # rubocop:disable Style/NumericPredicate
          GoodJob.deprecator.warn(
            %(Setting `config.good_job.cleanup_interval_seconds` to `0` will disable time-based cleanups in GoodJob v4. Set to `false` to disable, or `-1` to run every time.)
          )
          value = -1
        end
      elsif env.key?('GOOD_JOB_CLEANUP_INTERVAL_SECONDS')
        value = env['GOOD_JOB_CLEANUP_INTERVAL_SECONDS']
        if value.blank?
          GoodJob.deprecator.warn(
            %(Setting `GOOD_JOB_CLEANUP_INTERVAL_SECONDS` to `""` will no longer disable time-based cleanups in GoodJob v4. Set to `0` to disable, or `-1` to run every time.)
          )
          value = false
        elsif value == '0'
          value = false
        end
      else
        value = DEFAULT_CLEANUP_INTERVAL_SECONDS
      end

      value ? value.to_i : false
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
    # @return [nil, Integer]
    def probe_port
      (options[:probe_port] ||
        env['GOOD_JOB_PROBE_PORT']
      )&.to_i
    end

    # Probe server handler
    # @return [nil, Symbol]
    def probe_handler
      (options[:probe_handler] ||
        rails_config[:probe_handler] ||
        env['GOOD_JOB_PROBE_HANDLER']
      )&.to_sym
    end

    # Rack compliant application to be run on the ProbeServer
    # @return [nil, Class]
    def probe_app
      rails_config[:probe_app]
    end

    def enable_listen_notify
      return options[:enable_listen_notify] unless options[:enable_listen_notify].nil?
      return rails_config[:enable_listen_notify] unless rails_config[:enable_listen_notify].nil?
      return ActiveModel::Type::Boolean.new.cast(env['GOOD_JOB_ENABLE_LISTEN_NOTIFY']) unless env['GOOD_JOB_ENABLE_LISTEN_NOTIFY'].nil?

      DEFAULT_ENABLE_LISTEN_NOTIFY
    end

    def smaller_number_is_higher_priority
      rails_config[:smaller_number_is_higher_priority]
    end

    def dashboard_default_locale
      rails_config[:dashboard_default_locale] || DEFAULT_DASHBOARD_DEFAULT_LOCALE
    end

    # Whether running in a web server process.
    # @return [Boolean, nil]
    def in_webserver?
      return @_in_webserver unless @_in_webserver.nil?

      @_in_webserver = Rails.const_defined?(:Server) || begin
        self_caller = caller
        self_caller.grep(%r{config.ru}).any? || # EXAMPLE: config.ru:3:in `block in <main>' OR config.ru:3:in `new_from_string'
          self_caller.grep(%r{puma/request}).any? || # EXAMPLE: puma-5.6.4/lib/puma/request.rb:76:in `handle_request'
          self_caller.grep(%{/rack/handler/}).any? || # EXAMPLE: iodine-0.7.44/lib/rack/handler/iodine.rb:13:in `start'
          (Concurrent.on_jruby? && self_caller.grep(%r{jruby/rack/rails_booter}).any?) # EXAMPLE: uri:classloader:/jruby/rack/rails_booter.rb:83:in `load_environment'
      end || false
    end

    private

    def rails_config
      Rails.application.config.good_job
    end
  end
end
