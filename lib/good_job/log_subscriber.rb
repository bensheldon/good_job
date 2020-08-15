module GoodJob
  class LogSubscriber < ActiveSupport::LogSubscriber
    def create(event)
      good_job = event.payload[:good_job]

      debug do
        "GoodJob created job resource with id #{good_job.id}"
      end
    end

    def timer_task_finished(event)
      exception = event.payload[:error]
      return unless exception

      error do
        "GoodJob error: #{exception}\n #{exception.backtrace}"
      end
    end

    def job_finished(event)
      exception = event.payload[:error]
      return unless exception

      error do
        "GoodJob error: #{exception}\n #{exception.backtrace}"
      end
    end

    def scheduler_create_pools(event)
      max_threads = event.payload[:max_threads]
      poll_interval = event.payload[:poll_interval]
      performer_name = event.payload[:performer_name]
      process_id = event.payload[:process_id]

      info(tags: [process_id]) do
        "GoodJob started scheduler with queues=#{performer_name} max_threads=#{max_threads} poll_interval=#{poll_interval}."
      end
    end

    def scheduler_shutdown_start(event)
      process_id = event.payload[:process_id]

      info(tags: [process_id]) do
        "GoodJob shutting down scheduler..."
      end
    end

    def scheduler_shutdown(event)
      process_id = event.payload[:process_id]

      info(tags: [process_id]) do
        "GoodJob scheduler is shut down."
      end
    end

    def scheduler_restart_pools(event)
      process_id = event.payload[:process_id]

      info(tags: [process_id]) do
        "GoodJob scheduler has restarted."
      end
    end

    def perform_job(event)
      good_job = event.payload[:good_job]
      process_id = event.payload[:process_id]
      thread_name = event.payload[:thread_name]

      info(tags: [process_id, thread_name]) do
        "Executed GoodJob #{good_job.id}"
      end
    end

    def cleanup_preserved_jobs(event)
      timestamp = event.payload[:timestamp]
      deleted_records_count = event.payload[:deleted_records_count]

      info do
        "GoodJob deleted #{deleted_records_count} preserved #{'job'.pluralize(deleted_records_count)} finished before #{timestamp}."
      end
    end

    class << self
      def loggers
        @_loggers ||= [GoodJob.logger]
      end

      def logger
        @_logger ||= begin
                      logger = Logger.new(StringIO.new)
                      loggers.each do |each_logger|
                        logger.extend(ActiveSupport::Logger.broadcast(each_logger))
                      end
                      logger
                    end
      end

      def reset_logger
        @_logger = nil
      end
    end

    def logger
      GoodJob::LogSubscriber.logger
    end

    private

    def tag_logger(*tags, &block)
      tags = tags.dup.unshift("GoodJob").compact

      self.class.loggers.inject(block) do |inner, each_logger|
        if each_logger.respond_to?(:tagged)
          tags_for_logger = if each_logger.formatter.current_tags.include?("ActiveJob")
                              ["ActiveJob"] + tags
                            else
                              tags
                            end

          proc { each_logger.tagged(*tags_for_logger, &inner) }
        else
          inner
        end
      end.call
    end

    %w(info debug warn error fatal unknown).each do |level|
      class_eval <<-METHOD, __FILE__, __LINE__ + 1
        def #{level}(progname = nil, tags: [], &block)
          return unless logger

          tag_logger(*tags) do
            logger.#{level}(progname, &block)
          end
        end
      METHOD
    end
  end
end
