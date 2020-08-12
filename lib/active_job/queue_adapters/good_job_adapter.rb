module ActiveJob
  module QueueAdapters
    class GoodJobAdapter < GoodJob::Adapter
      def initialize(execution_mode: nil, max_threads: nil, poll_interval: nil, scheduler: nil, inline: false)
        configuration = GoodJob::Configuration.new({ execution_mode: execution_mode }, env: ENV)
        super(execution_mode: configuration.rails_execution_mode, max_threads: max_threads, poll_interval: poll_interval, scheduler: scheduler, inline: inline)
      end
    end
  end
end
