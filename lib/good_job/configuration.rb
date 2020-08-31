module GoodJob
  class Configuration
    attr_reader :options, :env

    def initialize(options, env: ENV)
      @options = options
      @env = env
    end

    def execution_mode(default: :external)
      if options[:execution_mode]
        options[:execution_mode]
      elsif env['GOOD_JOB_EXECUTION_MODE'].present?
        env['GOOD_JOB_EXECUTION_MODE'].to_sym
      else
        default
      end
    end

    def rails_execution_mode
      if execution_mode(default: nil)
        execution_mode
      elsif Rails.env.development?
        :inline
      elsif Rails.env.test?
        :inline
      else
        :external
      end
    end

    def max_threads
      (
        options[:max_threads] ||
        env['GOOD_JOB_MAX_THREADS'] ||
        env['RAILS_MAX_THREADS'] ||
        ActiveRecord::Base.connection_pool.size
      ).to_i
    end

    def queue_string
      options[:queues] ||
        env['GOOD_JOB_QUEUES'] ||
        '*'
    end

    def poll_interval
      (
        options[:poll_interval] ||
        env['GOOD_JOB_POLL_INTERVAL'] ||
        1
      ).to_i
    end

    def cleanup_preserved_jobs_before_seconds_ago
      (
        options[:before_seconds_ago] ||
        env['GOOD_JOB_CLEANUP_PRESERVED_JOBS_BEFORE_SECONDS_AGO'] ||
        24 * 60 * 60
      ).to_i
    end
  end
end
