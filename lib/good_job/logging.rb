module GoodJob
  module Logging
    extend ActiveSupport::Concern

    included do
      cattr_accessor :logger, default: ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(STDOUT))

      def self.tag_logger(*tags)
        if logger.respond_to?(:tagged)
          tags.unshift "GoodJob" unless logger.formatter.current_tags.include?("GoodJob")
          logger.tagged(*tags) { yield }
        else
          yield
        end
      end
    end

    class LogSubscriber < ActiveSupport::LogSubscriber
      def create(event)
        good_job = event.payload[:good_job]

        info do
          "Created GoodJob resource with id #{good_job.id}"
        end
      end

      def timer_task_finished(event)
        exception = event.payload[:error]
        return unless exception

        error do
          "ERROR: #{exception}\n #{exception.backtrace}"
        end
      end

      def job_finished(event)
        exception = event.payload[:error]
        return unless exception

        error do
          "ERROR: #{exception}\n #{exception.backtrace}"
        end
      end

      private

      def logger
        GoodJob.logger
      end

      def thread_name
        Thread.current.name || Thread.current.object_id
      end
    end
  end
end

GoodJob::Logging::LogSubscriber.attach_to :good_job
