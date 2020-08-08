module GoodJob
  class Adapter
    EXECUTION_MODES = [:async, :external, :inline].freeze

    def initialize(execution_mode: nil, max_threads: nil, poll_interval: nil, scheduler: nil, inline: false)
      if inline
        ActiveSupport::Deprecation.warn('GoodJob::Adapter#new(inline: true) is deprecated; use GoodJob::Adapter.new(execution_mode: :inline) instead')
        @execution_mode = :inline
      elsif execution_mode
        raise ArgumentError, "execution_mode: must be one of #{EXECUTION_MODES.join(', ')}." unless EXECUTION_MODES.include?(execution_mode)

        @execution_mode = execution_mode
      else
        @execution_mode = :external
      end

      @scheduler = scheduler
      if @execution_mode == :async && @scheduler.blank? # rubocop:disable Style/GuardClause
        timer_options = {}
        timer_options[:execution_interval] = poll_interval if poll_interval.present?

        pool_options = {}
        pool_options[:max_threads] = max_threads if max_threads.present?

        job_performer = GoodJob::Performer.new(GoodJob::Job, :perform_with_advisory_lock, name: '*')
        @scheduler = GoodJob::Scheduler.new(job_performer, timer_options: timer_options, pool_options: pool_options)
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

      @scheduler.create_thread if execute_async?

      good_job
    end

    def shutdown(wait: true)
      @scheduler&.shutdown(wait: wait)
    end

    def execute_async?
      @execution_mode == :async
    end

    def execute_externally?
      @execution_mode == :external
    end

    def execute_inline?
      @execution_mode == :inline
    end

    def inline?
      ActiveSupport::Deprecation.warn('GoodJob::Adapter::inline? is deprecated; use GoodJob::Adapter::execute_inline? instead')
      execute_inline?
    end
  end
end
