module ActiveJob
  module QueueAdapters
    class GoodJobAdapter < GoodJob::Adapter
      def initialize(execution_mode: nil)
        execution_mode = if execution_mode
                           execution_mode
                         elsif ENV['GOOD_JOB_EXECUTION_MODE'].present?
                           ENV['GOOD_JOB_EXECUTION_MODE'].to_sym
                         elsif Rails.env.development? || Rails.env.test?
                           :inline
                         else
                           :external
                         end

        super(execution_mode: execution_mode)
      end
    end
  end
end
