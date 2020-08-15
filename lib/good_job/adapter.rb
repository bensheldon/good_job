module GoodJob
  class Adapter
    EXECUTION_MODES = [:async, :external, :inline].freeze

    def initialize(execution_mode: nil, max_threads: nil, poll_interval: nil, scheduler: nil, inline: false)
      if inline && execution_mode.nil?
        ActiveSupport::Deprecation.warn('GoodJob::Adapter#new(inline: true) is deprecated; use GoodJob::Adapter.new(execution_mode: :inline) instead')
        execution_mode = :inline
      end

      configuration = GoodJob::Configuration.new({
                                                   execution_mode: execution_mode,
                                                   max_threads: max_threads,
                                                   poll_interval: poll_interval,
                                                 },
                                                 env: ENV)

      raise ArgumentError, "execution_mode: must be one of #{EXECUTION_MODES.join(', ')}." unless EXECUTION_MODES.include?(configuration.execution_mode)

      @execution_mode = configuration.execution_mode

      @scheduler = scheduler
      @scheduler = GoodJob::Scheduler.from_configuration(configuration) if @execution_mode == :async && @scheduler.blank?
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

      @scheduler.create_thread(queue_name: good_job.queue_name) if execute_async?

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
