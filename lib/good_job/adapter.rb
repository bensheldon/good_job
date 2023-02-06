# frozen_string_literal: true
module GoodJob
  #
  # ActiveJob Adapter.
  #
  class Adapter
    # @!attribute [r] instances
    #   @!scope class
    #   List of all instantiated Adapters in the current process.
    #   @return [Array<GoodJob::Adapter>, nil]
    cattr_reader :instances, default: [], instance_reader: false

    # @param execution_mode [Symbol, nil] specifies how and where jobs should be executed. You can also set this with the environment variable +GOOD_JOB_EXECUTION_MODE+.
    #
    #  - +:inline+ executes jobs immediately in whatever process queued them (usually the web server process). This should only be used in test and development environments.
    #  - +:external+ causes the adapter to enqueue jobs, but not execute them. When using this option (the default for production environments), you'll need to use the command-line tool to actually execute your jobs.
    #  - +:async+ (or +:async_server+) executes jobs in separate threads within the Rails web server process (`bundle exec rails server`). It can be more economical for small workloads because you don't need a separate machine or environment for running your jobs, but if your web server is under heavy load or your jobs require a lot of resources, you should choose +:external+ instead.
    #    When not in the Rails web server, jobs will execute in +:external+ mode to ensure jobs are not executed within `rails console`, `rails db:migrate`, `rails assets:prepare`, etc.
    #  - +:async_all+ executes jobs in any Rails process.
    #
    #  The default value depends on the Rails environment:
    #
    #  - +development+: +:async:+
    #   -+test+: +:inline+
    #  - +production+ and all other environments: +:external+
    #
    def initialize(execution_mode: nil)
      @_execution_mode_override = execution_mode
      GoodJob::Configuration.validate_execution_mode(@_execution_mode_override) if @_execution_mode_override

      self.class.instances << self
      start_async if GoodJob.async_ready?
    end

    # Enqueues the ActiveJob job to be performed.
    # For use by Rails; you should generally not call this directly.
    # @param active_job [ActiveJob::Base] the job to be enqueued from +#perform_later+
    # @return [GoodJob::Execution]
    def enqueue(active_job)
      enqueue_at(active_job, nil)
    end

    # Enqueues multiple ActiveJob instances at once
    # @param active_jobs [Array<ActiveJob::Base>] jobs to be enqueued
    # @return [Integer] number of jobs that were successfully enqueued
    def enqueue_all(active_jobs)
      active_jobs = Array(active_jobs)
      return 0 if active_jobs.empty?

      current_time = Time.current
      executions = active_jobs.map do |active_job|
        GoodJob::Execution.build_for_enqueue(active_job, {
                                               id: SecureRandom.uuid,
                                               created_at: current_time,
                                               updated_at: current_time,
                                             })
      end

      inline_executions = []
      GoodJob::Execution.transaction(requires_new: true, joinable: false) do
        results = GoodJob::Execution.insert_all(executions.map(&:attributes), returning: %w[id active_job_id]) # rubocop:disable Rails/SkipsModelValidations

        job_id_to_provider_job_id = results.each_with_object({}) { |result, hash| hash[result['active_job_id']] = result['id'] }
        active_jobs.each do |active_job|
          active_job.provider_job_id = job_id_to_provider_job_id[active_job.job_id]
        end
        executions.each do |execution|
          execution.instance_variable_set(:@new_record, false) if job_id_to_provider_job_id[execution.active_job_id]
        end
        executions = executions.select(&:persisted?) # prune unpersisted executions

        if execute_inline?
          inline_executions = executions.select { |execution| (execution.scheduled_at.nil? || execution.scheduled_at <= Time.current) }
          inline_executions.each(&:advisory_lock!)
        end
      end

      begin
        until inline_executions.empty?
          begin
            inline_execution = inline_executions.shift
            inline_result = inline_execution.perform
          ensure
            inline_execution.advisory_unlock
            inline_execution.run_callbacks(:perform_unlocked)
          end
          raise inline_result.unhandled_error if inline_result.unhandled_error
        end
      ensure
        inline_executions.each(&:advisory_unlock)
      end

      non_inline_executions = executions.reject(&:finished_at)
      if non_inline_executions.any?
        job_id_to_active_jobs = active_jobs.index_by(&:job_id)
        non_inline_executions.group_by(&:queue_name).each do |queue_name, executions_by_queue|
          executions_by_queue.group_by(&:scheduled_at).each do |scheduled_at, executions_by_queue_and_scheduled_at|
            state = { queue_name: queue_name, count: executions_by_queue_and_scheduled_at.size }
            state[:scheduled_at] = scheduled_at if scheduled_at

            executed_locally = execute_async? && @scheduler&.create_thread(state)
            unless executed_locally
              state[:count] = job_id_to_active_jobs.values_at(*executions_by_queue_and_scheduled_at.map(&:active_job_id)).count { |active_job| send_notify?(active_job) }
              Notifier.notify(state) unless state[:count].zero?
            end
          end
        end
      end

      active_jobs.count(&:provider_job_id)
    end

    # Enqueues an ActiveJob job to be run at a specific time.
    # For use by Rails; you should generally not call this directly.
    # @param active_job [ActiveJob::Base] the job to be enqueued from +#perform_later+
    # @param timestamp [Integer, nil] the epoch time to perform the job
    # @return [GoodJob::Execution]
    def enqueue_at(active_job, timestamp)
      scheduled_at = timestamp ? Time.zone.at(timestamp) : nil

      # If there is a currently open Bulk in the current thread, direct the
      # job there to be enqueued using enqueue_all
      return if GoodJob::Bulk.capture(active_job, queue_adapter: self)

      will_execute_inline = execute_inline? && (scheduled_at.nil? || scheduled_at <= Time.current)
      execution = GoodJob::Execution.enqueue(
        active_job,
        scheduled_at: scheduled_at,
        create_with_advisory_lock: will_execute_inline
      )

      if will_execute_inline
        begin
          result = execution.perform
        ensure
          execution.advisory_unlock
          execution.run_callbacks(:perform_unlocked)
        end
        raise result.unhandled_error if result.unhandled_error
      else
        job_state = { queue_name: execution.queue_name }
        job_state[:scheduled_at] = execution.scheduled_at if execution.scheduled_at

        executed_locally = execute_async? && @scheduler&.create_thread(job_state)
        Notifier.notify(job_state) if !executed_locally && send_notify?(active_job)
      end

      execution
    end

    # Shut down the thread pool executors.
    # @param timeout [nil, Numeric, Symbol] Seconds to wait for active threads.
    #   * +nil+, the scheduler will trigger a shutdown but not wait for it to complete.
    #   * +-1+, the scheduler will wait until the shutdown is complete.
    #   * +0+, the scheduler will immediately shutdown and stop any threads.
    #   * A positive number will wait that many seconds before stopping any remaining active threads.
    # @return [void]
    def shutdown(timeout: :default)
      timeout = if timeout == :default
                  GoodJob.configuration.shutdown_timeout
                else
                  timeout
                end

      executables = [@notifier, @poller, @scheduler].compact
      GoodJob._shutdown_all(executables, timeout: timeout)
      @_async_started = false
    end

    # This adapter's execution mode
    # @return [Symbol, nil]
    def execution_mode
      @_execution_mode_override || GoodJob.configuration.execution_mode
    end

    # Whether in +:async+ execution mode.
    # @return [Boolean]
    def execute_async?
      execution_mode == :async_all ||
        (execution_mode.in?([:async, :async_server]) && in_server_process?)
    end

    # Whether in +:external+ execution mode.
    # @return [Boolean]
    def execute_externally?
      execution_mode.nil? ||
        execution_mode == :external ||
        (execution_mode.in?([:async, :async_server]) && !in_server_process?)
    end

    # Whether in +:inline+ execution mode.
    # @return [Boolean]
    def execute_inline?
      execution_mode == :inline
    end

    # Start async executors
    # @return [void]
    def start_async
      return unless execute_async?

      @notifier = GoodJob::Notifier.new(enable_listening: GoodJob.configuration.enable_listen_notify)
      @poller = GoodJob::Poller.new(poll_interval: GoodJob.configuration.poll_interval)
      @scheduler = GoodJob::Scheduler.from_configuration(GoodJob.configuration, warm_cache_on_initialize: true)
      @notifier.recipients << [@scheduler, :create_thread]
      @poller.recipients << [@scheduler, :create_thread]

      @cron_manager = GoodJob::CronManager.new(GoodJob.configuration.cron_entries, start_on_initialize: true) if GoodJob.configuration.enable_cron?

      @_async_started = true
    end

    # Whether the async executors are running
    # @return [Boolean]
    def async_started?
      @_async_started
    end

    private

    # Whether running in a web server process.
    # @return [Boolean, nil]
    def in_server_process?
      return @_in_server_process if defined? @_in_server_process

      @_in_server_process = Rails.const_defined?(:Server) || begin
        self_caller = caller

        self_caller.grep(%r{config.ru}).any? || # EXAMPLE: config.ru:3:in `block in <main>' OR config.ru:3:in `new_from_string'
          self_caller.grep(%r{puma/request}).any? || # EXAMPLE: puma-5.6.4/lib/puma/request.rb:76:in `handle_request'
          self_caller.grep(%{/rack/handler/}).any? || # EXAMPLE: iodine-0.7.44/lib/rack/handler/iodine.rb:13:in `start'
          (Concurrent.on_jruby? && self_caller.grep(%r{jruby/rack/rails_booter}).any?) # EXAMPLE: uri:classloader:/jruby/rack/rails_booter.rb:83:in `load_environment'
      end
    end

    def send_notify?(active_job)
      return true unless active_job.respond_to?(:good_job_notify)
      return false unless GoodJob.configuration.enable_listen_notify

      !(active_job.good_job_notify == false || (active_job.class.good_job_notify == false && active_job.good_job_notify.nil?))
    end
  end
end
