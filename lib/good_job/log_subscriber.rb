# frozen_string_literal: true
module GoodJob
  #
  # Listens to GoodJob notifications and logs them.
  #
  # Each method corresponds to the name of a notification. For example, when
  # the {Scheduler} shuts down, it sends a notification named
  # +"scheduler_shutdown.good_job"+ and the {#scheduler_shutdown} method will
  # be called here. See the
  # {https://api.rubyonrails.org/classes/ActiveSupport/LogSubscriber.html ActiveSupport::LogSubscriber}
  # documentation for more.
  #
  class LogSubscriber < ActiveSupport::LogSubscriber
    # @!group Notifications

    # @!macro notification_responder
    #   Responds to the +$0.good_job+ notification.
    #   @param event [ActiveSupport::Notifications::Event]
    #   @return [void]
    def create(event)
      # FIXME: This method does not match any good_job notifications.
      execution = event.payload[:execution]

      debug do
        "GoodJob created job resource with id #{execution.id}"
      end
    end

    # @!macro notification_responder
    def finished_timer_task(event)
      exception = event.payload[:error]
      return unless exception

      error do
        "GoodJob error: #{exception.class}: #{exception}\n #{exception.backtrace}"
      end
    end

    # @!macro notification_responder
    def finished_job_task(event)
      exception = event.payload[:error]
      return unless exception

      error do
        "GoodJob error: #{exception.class}: #{exception}\n #{exception.backtrace}"
      end
    end

    # @!macro notification_responder
    def scheduler_create_pool(event)
      max_threads = event.payload[:max_threads]
      performer_name = event.payload[:performer_name]
      process_id = event.payload[:process_id]

      info(tags: [process_id]) do
        "GoodJob started scheduler with queues=#{performer_name} max_threads=#{max_threads}."
      end
    end

    # @!macro notification_responder
    def cron_manager_start(event)
      cron_entries = event.payload[:cron_entries]
      cron_jobs_count = cron_entries.size

      info do
        "GoodJob started cron with #{cron_jobs_count} #{'job'.pluralize(cron_jobs_count)}."
      end
    end

    # @!macro notification_responder
    def scheduler_shutdown_start(event)
      process_id = event.payload[:process_id]

      info(tags: [process_id]) do
        "GoodJob shutting down scheduler..."
      end
    end

    # @!macro notification_responder
    def scheduler_shutdown(event)
      process_id = event.payload[:process_id]

      info(tags: [process_id]) do
        "GoodJob scheduler is shut down."
      end
    end

    # @!macro notification_responder
    def scheduler_restart_pools(event)
      process_id = event.payload[:process_id]

      info(tags: [process_id]) do
        "GoodJob scheduler has restarted."
      end
    end

    # @!macro notification_responder
    def perform_job(event)
      execution = event.payload[:execution]
      process_id = event.payload[:process_id]
      thread_name = event.payload[:thread_name]

      info(tags: [process_id, thread_name]) do
        "Executed GoodJob #{execution.id}"
      end
    end

    # @!macro notification_responder
    def notifier_listen(event) # rubocop:disable Lint/UnusedMethodArgument
      info do
        "Notifier subscribed with LISTEN"
      end
    end

    # @!macro notification_responder
    def notifier_notified(event)
      payload = event.payload[:payload]

      debug do
        "Notifier received payload: #{payload}"
      end
    end

    # @!macro notification_responder
    def notifier_notify_error(event)
      exception = event.payload[:error]

      error do
        "Notifier errored: #{exception.class}: #{exception}\n #{exception.backtrace}"
      end
    end

    # @!macro notification_responder
    def notifier_unlisten(event) # rubocop:disable Lint/UnusedMethodArgument
      info do
        "Notifier unsubscribed with UNLISTEN"
      end
    end

    # @!macro notification_responder
    def cleanup_preserved_jobs(event)
      timestamp = event.payload[:timestamp]
      destroyed_records_count = event.payload[:destroyed_records_count]

      info do
        "GoodJob destroyed #{destroyed_records_count} preserved #{'job'.pluralize(destroyed_records_count)} finished before #{timestamp}."
      end
    end

    # @!endgroup

    # Get the logger associated with this {LogSubscriber} instance.
    # @return [Logger]
    def logger
      GoodJob::LogSubscriber.logger
    end

    class << self
      # Tracks all loggers that {LogSubscriber} is writing to. You can write to
      # multiple logs by appending to this array. After updating it, you should
      # usually call {LogSubscriber.reset_logger} to make sure they are all
      # written to.
      #
      # Defaults to {GoodJob.logger}.
      # @return [Array<Logger>]
      # @example Write to STDOUT and to a file:
      #   GoodJob::LogSubscriber.loggers << ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(STDOUT))
      #   GoodJob::LogSubscriber.loggers << ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new("log/my_logs.log"))
      #   GoodJob::LogSubscriber.reset_logger
      def loggers
        @_loggers ||= [GoodJob.logger]
      end

      # Represents all the loggers attached to {LogSubscriber} with a single
      # logging interface. Writing to this logger is a shortcut for writing to
      # each of the loggers in {LogSubscriber.loggers}.
      # @return [Logger]
      def logger
        @_logger ||= begin
          logger = Logger.new(StringIO.new)
          loggers.each do |each_logger|
            logger.extend(ActiveSupport::Logger.broadcast(each_logger))
          end
          logger
        end
      end

      # Reset {LogSubscriber.logger} and force it to rebuild a new shortcut to
      # all the loggers in {LogSubscriber.loggers}. You should usually call
      # this after modifying the {LogSubscriber.loggers} array.
      # @return [void]
      def reset_logger
        @_logger = nil
      end
    end

    private

    # Add "GoodJob" plus any specified tags to every
    # {ActiveSupport::TaggedLogging} logger in {LogSubscriber.loggers}. Tags
    # are only applicable inside the block passed to this method.
    # @yield [void]
    # @return [void]
    def tag_logger(*tags, &block)
      tags = tags.dup.unshift("GoodJob").compact
      good_job_tag = ["ActiveJob"].freeze

      self.class.loggers.inject(block) do |inner, each_logger|
        if each_logger.respond_to?(:tagged) && each_logger.formatter
          tags_for_logger = if each_logger.formatter.current_tags.include?("ActiveJob")
                              good_job_tag + tags
                            else
                              tags
                            end

          proc { each_logger.tagged(*tags_for_logger, &inner) }
        else
          inner
        end
      end.call
    end

    # Ensure that the standard logging methods include "GoodJob" as a tag and
    # that they include a second argument allowing callers to specify ad-hoc
    # tags to include in the message.
    #
    # For example, to include the tag "ForFunsies" on an +info+ message:
    #
    #     self.info("Some message", tags: ["ForFunsies"])
    #
    %w(info debug warn error fatal unknown).each do |level|
      class_eval <<-METHOD, __FILE__, __LINE__ + 1
        def #{level}(progname = nil, tags: [], &block)   # def info(progname = nil, tags: [], &block)
          return unless logger                           #   return unless logger
                                                         #
          tag_logger(*tags) do                           #   tag_logger(*tags) do
            logger.#{level}(progname, &block)            #     logger.info(progname, &block)
          end                                            #   end
        end                                              #
      METHOD
    end
  end
end
