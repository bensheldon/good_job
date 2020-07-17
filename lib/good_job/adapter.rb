module GoodJob
  class Adapter
    EXECUTION_MODES = [:inline, :external].freeze # TODO: async

    def initialize(execution_mode: nil, inline: false)
      if inline
        ActiveSupport::Deprecation.warn('GoodJob::Adapter#new(inline: true) is deprecated; use GoodJob::Adapter.new(execution_mode: :inline) instead')
        @execution_mode = :inline
      elsif execution_mode
        raise ArgumentError, "execution_mode: must be one of #{EXECUTION_MODES.join(', ')}." unless EXECUTION_MODES.include?(execution_mode)

        @execution_mode = execution_mode
      else
        @execution_mode = :external
      end
    end

    def enqueue(active_job)
      enqueue_at(active_job, nil)
    end

    def enqueue_at(active_job, timestamp)
      good_job = GoodJob::Job.enqueue(
        active_job,
        scheduled_at: timestamp ? Time.zone.at(timestamp) : nil,
        create_with_advisory_lock: execute_inline?
      )

      if execute_inline?
        begin
          good_job.perform
        ensure
          good_job.advisory_unlock
        end
      end

      good_job
    end

    def shutdown(wait: true) # rubocop:disable Lint/UnusedMethodArgument
      nil
    end

    def execute_inline?
      @execution_mode == :inline
    end

    def inline?
      ActiveSupport::Deprecation.warn('GoodJob::Adapter::inline? is deprecated; use GoodJob::Adapter::execute_inline? instead')
      execute_inline?
    end

    def execute_externally?
      @execution_mode == :external
    end
  end
end
