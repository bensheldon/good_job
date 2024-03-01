# frozen_string_literal: true

module GoodJob
  # Provides methods for determining the status of the
  # current job execution thread. This is useful for determining
  # whether to continue processing a job or to shut down gracefully.
  module ThreadStatus
    extend ActiveSupport::Concern

    class_methods do
      # Whether the current job execution thread is in a running state.
      # @return [Boolean]
      def current_thread_running?
        scheduler = Thread.current[:good_job_scheduler]
        scheduler ? scheduler.running? : true
      end

      # Whether the current job execution thread is shutting down
      # (the opposite of running).
      # @return [Boolean]
      def current_thread_shutting_down?
        scheduler = Thread.current[:good_job_scheduler]
        scheduler && !scheduler.running?
      end
    end
  end
end
