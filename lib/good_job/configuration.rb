module GoodJob
  #
  # +GoodJob::Configuration+ provides normalized configuration information to
  # the rest of GoodJob. It combines environment information with explicitly
  # set options to get the final values for each option.
  #
  class Configuration
    # Default number of threads to use per {Scheduler}
    DEFAULT_MAX_THREADS = 5
    # Default number of seconds between polls for jobs
    DEFAULT_POLL_INTERVAL = 5
    # Default number of seconds to preserve jobs for {CLI#cleanup_preserved_jobs}
    DEFAULT_CLEANUP_PRESERVED_JOBS_BEFORE_SECONDS_AGO = 24 * 60 * 60

    # @!attribute [r] options
    #   The options that were explicitly set when initializing +Configuration+.
    #   @return [Hash]
    #
    # @!attribute [r] env
    #   The environment from which to read GoodJob's environment variables. By
    #   default, this is the current process's environment, but it can be set
    #   to something else in {#initialize}.
    #   @return [Hash]
    attr_reader :options, :env

    # @param options [Hash] Any explicitly specified configuration options to
    #   use. Keys are symbols that match the various methods on this class.
    # @param env [Hash] A +Hash+ from which to read environment variables that
    #   might specify additional configuration values.
    def initialize(options, env: ENV)
      @options = options
      @env = env
    end

    # Specifies how and where jobs should be executed. See {Adapter#initialize}
    # for more details on possible values.
    #
    # When running inside a Rails app, you may want to use
    # {#rails_execution_mode}, which takes the current Rails environment into
    # account when determining the final value.
    #
    # @param default [Symbol]
    #   Value to use if none was specified in the configuration.
    # @return [Symbol]
    def execution_mode(default: :external)
      if options[:execution_mode]
        options[:execution_mode]
      elsif env['GOOD_JOB_EXECUTION_MODE'].present?
        env['GOOD_JOB_EXECUTION_MODE'].to_sym
      else
        default
      end
    end

    # Like {#execution_mode}, but takes the current Rails environment into
    # account (e.g. in the +test+ environment, it falls back to +:inline+).
    # @return [Symbol]
    def rails_execution_mode
      if execution_mode(default: nil)
        execution_mode
      elsif Rails.env.development? || Rails.env.test?
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
      options[:queues] ||
        env['GOOD_JOB_QUEUES'] ||
        '*'
    end

    # The number of seconds between polls for jobs. GoodJob will execute jobs
    # on queues continuously until a queue is empty, at which point it will
    # poll (using this interval) for new queued jobs to execute.
    # @return [Integer]
    def poll_interval
      (
        options[:poll_interval] ||
        env['GOOD_JOB_POLL_INTERVAL'] ||
        DEFAULT_POLL_INTERVAL
      ).to_i
    end

    def cleanup_preserved_jobs_before_seconds_ago
      (
        options[:before_seconds_ago] ||
        env['GOOD_JOB_CLEANUP_PRESERVED_JOBS_BEFORE_SECONDS_AGO'] ||
        DEFAULT_CLEANUP_PRESERVED_JOBS_BEFORE_SECONDS_AGO
      ).to_i
    end
  end
end
