require 'thor'

module GoodJob
  class CLI < Thor
    RAILS_ENVIRONMENT_RB = File.expand_path("config/environment.rb")

    desc :start, "Start job worker"
    method_option :max_threads,
                  type: :numeric,
                  desc: "Maximum number of threads to use for working jobs (default: ActiveRecord::Base.connection_pool.size)"
    method_option :queues,
                  type: :string,
                  banner: "queue1,queue2(;queue3,queue4:5;-queue1,queue2)",
                  desc: "Queues to work from. Separate multiple queues with commas; exclude queues with a leading minus; separate isolated execution pools with semicolons and threads with colons (default: *)"
    method_option :poll_interval,
                  type: :numeric,
                  desc: "Interval between polls for available jobs in seconds (default: 1)"
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

    desc :cleanup_preserved_jobs, "Delete preserved job records"
    method_option :before_seconds_ago,
                  type: :numeric,
                  default: 24 * 60 * 60,
                  desc: "Delete records finished more than this many seconds ago"

    def cleanup_preserved_jobs
      set_up_application!

      timestamp = Time.current - options[:before_seconds_ago]
      ActiveSupport::Notifications.instrument("cleanup_preserved_jobs.good_job", { before_seconds_ago: options[:before_seconds_ago], timestamp: timestamp }) do |payload|
        deleted_records_count = GoodJob::Job.finished(timestamp).delete_all

        payload[:deleted_records_count] = deleted_records_count
      end
    end

    no_commands do
      def set_up_application!
        require RAILS_ENVIRONMENT_RB
        return unless defined?(GOOD_JOB_LOG_TO_STDOUT) && GOOD_JOB_LOG_TO_STDOUT && !ActiveSupport::Logger.logger_outputs_to?(GoodJob.logger, STDOUT)

        GoodJob::LogSubscriber.loggers << ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(STDOUT))
        GoodJob::LogSubscriber.reset_logger
      end
    end
  end
end
