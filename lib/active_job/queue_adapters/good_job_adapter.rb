module ActiveJob # :nodoc:
  module QueueAdapters # :nodoc:
    # See {GoodJob::Adapter} for details.
    class GoodJobAdapter < GoodJob::Adapter
      def initialize(**options)
        configuration = GoodJob::Configuration.new(options, env: ENV)
        super(**options.merge(execution_mode: configuration.rails_execution_mode))
      end
    end
  end
end
