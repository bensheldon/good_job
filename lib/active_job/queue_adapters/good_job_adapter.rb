module ActiveJob
  module QueueAdapters
    class GoodJobAdapter < GoodJob::Adapter
      def initialize(execution_mode: nil, max_threads: nil, poll_interval: nil, scheduler: nil)
        execution_mode = if execution_mode
                           execution_mode
                         elsif ENV['GOOD_JOB_EXECUTION_MODE'].present?
                           ENV['GOOD_JOB_EXECUTION_MODE'].to_sym
                         elsif Rails.env.development?
                           :inline
                         elsif Rails.env.test?
                           :inline
                         else
                           :external
                         end

        if execution_mode == :async && scheduler.blank?
          max_threads = (
            max_threads.presence ||
            ENV['GOOD_JOB_MAX_THREADS'] ||
            ENV['RAILS_MAX_THREADS'] ||
            ActiveRecord::Base.connection_pool.size
          ).to_i

          poll_interval = (
            poll_interval.presence ||
            ENV['GOOD_JOB_POLL_INTERVAL'] ||
            1
          ).to_i
        end

        super(execution_mode: execution_mode, max_threads: max_threads, poll_interval: poll_interval, scheduler: scheduler)
      end
    end
  end
end
