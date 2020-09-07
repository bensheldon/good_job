require 'thor'

module GoodJob
  #
  # Implements the +good_job+ command-line tool, which executes jobs and
  # provides other utilities. The actual entry point is in +exe/good_job+, but
  # it just sets up and calls this class.
  #
  # The +good_job+ command-line tool is based on Thor, a CLI framework for
  # Ruby. For more on general usage, see http://whatisthor.com/ and
  # https://github.com/erikhuda/thor/wiki.
  #
  class CLI < Thor
    # Path to the local Rails application's environment configuration.
    # Requiring this loads the application's configuration and classes.
    RAILS_ENVIRONMENT_RB = File.expand_path("config/environment.rb")

    # @!macro thor.desc
    #   @!method $1
    #   @return [void]
    #   The +good_job $1+ command. $2
    desc :start, "Executes queued jobs."
    long_desc <<~DESCRIPTION
      Executes queued jobs.

      All options can be configured with environment variables.
      See option descriptions for the matching environment variable name.

      == Configuring queues
      \x5Separate multiple queues with commas; exclude queues with a leading minus;
      separate isolated execution pools with semicolons and threads with colons.

    DESCRIPTION
    method_option :max_threads,
                  type: :numeric,
                  banner: 'COUNT',
                  desc: "Maximum number of threads to use for working jobs. (env var: GOOD_JOB_MAX_THREADS, default: 5)"
    method_option :queues,
                  type: :string,
                  banner: "QUEUE_LIST",
                  desc: "Queues to work from. (env var: GOOD_JOB_QUEUES, default: *)"
    method_option :poll_interval,
                  type: :numeric,
                  banner: 'SECONDS',
                  desc: "Interval between polls for available jobs in seconds (env var: GOOD_JOB_POLL_INTERVAL, default: 1)"
    def start
      set_up_application!

      notifier = GoodJob::Notifier.new
      configuration = GoodJob::Configuration.new(options)
      scheduler = GoodJob::Scheduler.from_configuration(configuration)
      notifier.recipients << [scheduler, :create_thread]

      @stop_good_job_executable = false
      %w[INT TERM].each do |signal|
        trap(signal) { @stop_good_job_executable = true }
      end

      Kernel.loop do
        sleep 0.1
        break if @stop_good_job_executable || scheduler.shutdown? || notifier.shutdown?
      end

      notifier.shutdown
      scheduler.shutdown
    end

    default_task :start

    # @!macro thor.desc
    desc :cleanup_preserved_jobs, "Deletes preserved job records."
    long_desc <<~DESCRIPTION
      Deletes preserved job records.

      By default, GoodJob deletes job records when the job is performed and this
      command is not necessary.

      However, when `GoodJob.preserve_job_records = true`, the jobs will be
      preserved in the database. This is useful when wanting to analyze or
      inspect job performance.

      If you are preserving job records this way, use this command regularly
      to delete old records and preserve space in your database.

    DESCRIPTION
    method_option :before_seconds_ago,
                  type: :numeric,
                  banner: 'SECONDS',
                  desc: "Delete records finished more than this many seconds ago (env var: GOOD_JOB_CLEANUP_PRESERVED_JOBS_BEFORE_SECONDS_AGO, default: 86400)"
    def cleanup_preserved_jobs
      set_up_application!

      configuration = GoodJob::Configuration.new(options)

      timestamp = Time.current - configuration.cleanup_preserved_jobs_before_seconds_ago

      ActiveSupport::Notifications.instrument(
        "cleanup_preserved_jobs.good_job",
        { before_seconds_ago: configuration.cleanup_preserved_jobs_before_seconds_ago, timestamp: timestamp }
      ) do |payload|
        deleted_records_count = GoodJob::Job.finished(timestamp).delete_all

        payload[:deleted_records_count] = deleted_records_count
      end
    end

    no_commands do
      # Load the current Rails application and configuration that the good_job
      # command-line tool should be working within.
      #
      # GoodJob components that need access to constants, classes, etc. from
      # Rails or from the application can be set up here.
      def set_up_application!
        require RAILS_ENVIRONMENT_RB
        return unless defined?(GOOD_JOB_LOG_TO_STDOUT) && GOOD_JOB_LOG_TO_STDOUT && !ActiveSupport::Logger.logger_outputs_to?(GoodJob.logger, $stdout)

        GoodJob::LogSubscriber.loggers << ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new($stdout))
        GoodJob::LogSubscriber.reset_logger
      end
    end
  end
end
