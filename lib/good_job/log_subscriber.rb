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

      info_and_stdout(tags: [process_id]) do
        "GoodJob started scheduler with queues=#{performer_name} max_threads=#{max_threads} poll_interval=#{poll_interval}."
      end
    end

    def scheduler_shutdown_start(event)
      process_id = event.payload[:process_id]

      info_and_stdout(tags: [process_id]) do
        "GoodJob shutting down scheduler..."
      end
    end

    def scheduler_shutdown(event)
      process_id = event.payload[:process_id]

      info_and_stdout(tags: [process_id]) do
        "GoodJob scheduler is shut down."
      end
    end

    def scheduler_restart_pools(event)
      process_id = event.payload[:process_id]

      info_and_stdout(tags: [process_id]) do
        "GoodJob scheduler has restarted."
      end
    end

    def cleanup_preserved_jobs(event)
      timestamp = event.payload[:timestamp]
      deleted_records_count = event.payload[:deleted_records_count]

      info_and_stdout do
        "GoodJob deleted #{deleted_records_count} preserved #{'job'.pluralize(deleted_records_count)} finished before #{timestamp}."
      end
    end

    private

    def logger
      GoodJob.logger
    end

    %w(info debug warn error fatal unknown).each do |level|
      class_eval <<-METHOD, __FILE__, __LINE__ + 1
        def #{level}(progname = nil, tags: [], &block)
          return unless logger

          if logger.respond_to?(:tagged)
            tags.unshift "GoodJob" unless logger.formatter.current_tags.include?("GoodJob")
            logger.tagged(*tags.compact) do
              logger.#{level}(progname, &block)
            end
          else
            logger.#{level}(progname, &block)
          end
        end
      METHOD
    end

    def info_and_stdout(progname = nil, tags: [], &block)
      unless ActiveSupport::Logger.logger_outputs_to?(logger, STDOUT)
        tags_string = (['GoodJob'] + tags).map { |t| "[#{t}]" }.join(' ')
        stdout_message = "#{tags_string}#{yield}"
        $stdout.puts stdout_message
      end

      info(progname, tags: [], &block)
    end

    def thread_name
      Thread.current.name || Thread.current.object_id
    end
  end
end
