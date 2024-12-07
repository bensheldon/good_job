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
    cattr_reader :instances, default: Concurrent::Array.new, instance_reader: false

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
    def initialize(execution_mode: nil, _capsule: GoodJob.capsule) # rubocop:disable Lint/UnderscorePrefixedVariableName
      @_execution_mode_override = execution_mode
      GoodJob::Configuration.validate_execution_mode(@_execution_mode_override) if @_execution_mode_override
      @capsule = _capsule

      start_async if GoodJob.async_ready?
      self.class.instances << self
    end

    # Enqueues the ActiveJob job to be performed.
    # For use by Rails; you should generally not call this directly.
    # @param active_job [ActiveJob::Base] the job to be enqueued from +#perform_later+
    # @return [GoodJob::Job]
    def enqueue(active_job)
      enqueue_at(active_job, nil)
    end

    # Defines if enqueueing this job from inside an Active Record transaction
    # automatically defers the enqueue to after the transaction commit.
    def enqueue_after_transaction_commit?
      GoodJob.configuration.enqueue_after_transaction_commit
    end

    # Enqueues multiple ActiveJob instances at once
    # @param active_jobs [Array<ActiveJob::Base>] jobs to be enqueued
    # @return [Integer] number of jobs that were successfully enqueued
    def enqueue_all(active_jobs)
      active_jobs = Array(active_jobs)
      return 0 if active_jobs.empty?

      Rails.application.executor.wrap do
        current_time = Time.current
        jobs = active_jobs.map do |active_job|
          GoodJob::Job.build_for_enqueue(active_job).tap do |job|
            job.scheduled_at = current_time if job.scheduled_at == job.created_at
            job.created_at = current_time
            job.updated_at = current_time
          end
        end

        inline_jobs = []
        GoodJob::Job.transaction(requires_new: true, joinable: false) do
          job_attributes = jobs.map(&:attributes)
          results = GoodJob::Job.insert_all(job_attributes, returning: %w[id active_job_id]) # rubocop:disable Rails/SkipsModelValidations

          job_id_to_provider_job_id = results.each_with_object({}) { |result, hash| hash[result['active_job_id']] = result['id'] }
          active_jobs.each do |active_job|
            active_job.provider_job_id = job_id_to_provider_job_id[active_job.job_id]
            active_job.successfully_enqueued = active_job.provider_job_id.present? if active_job.respond_to?(:successfully_enqueued=)
          end
          jobs.each do |job|
            job.instance_variable_set(:@new_record, false) if job_id_to_provider_job_id[job.active_job_id]
          end
          jobs = jobs.select(&:persisted?) # prune unpersisted jobs

          if execute_inline?
            inline_jobs = jobs.select { |job| job.scheduled_at.nil? || job.scheduled_at <= Time.current }
            inline_jobs.each(&:advisory_lock!)
          end
        end

        if inline_jobs.any?
          deferred = InlineBuffer.defer?
          InlineBuffer.perform_now_or_defer do
            @capsule.tracker.register do
              until inline_jobs.empty?
                inline_job = inline_jobs.shift
                perform_inline(inline_job, notify: deferred ? send_notify?(inline_job) : false)
              end
            ensure
              inline_jobs.each(&:advisory_unlock)
            end
          end
        end

        non_inline_jobs = if InlineBuffer.defer?
                            jobs - inline_jobs
                          else
                            jobs.reject(&:finished_at)
                          end
        if non_inline_jobs.any?
          job_id_to_active_jobs = active_jobs.index_by(&:job_id)
          non_inline_jobs.group_by(&:queue_name).each do |queue_name, jobs_by_queue|
            jobs_by_queue.group_by(&:scheduled_at).each do |scheduled_at, jobs_by_queue_and_scheduled_at|
              state = { queue_name: queue_name, count: jobs_by_queue_and_scheduled_at.size }
              state[:scheduled_at] = scheduled_at if scheduled_at

              executed_locally = execute_async? && @capsule&.create_thread(state)
              unless executed_locally
                state[:count] = job_id_to_active_jobs.values_at(*jobs_by_queue_and_scheduled_at.map(&:active_job_id)).count { |active_job| send_notify?(active_job) }
                Notifier.notify(state) unless state[:count].zero?
              end
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
    # @return [GoodJob::Job]
    def enqueue_at(active_job, timestamp)
      scheduled_at = timestamp ? Time.zone.at(timestamp) : nil

      # If there is a currently open Bulk in the current thread, direct the
      # job there to be enqueued using enqueue_all
      return if GoodJob::Bulk.capture(active_job, queue_adapter: self)

      Rails.application.executor.wrap do
        will_execute_inline = execute_inline? && (scheduled_at.nil? || scheduled_at <= Time.current)
        will_retry_inline = will_execute_inline && CurrentThread.job&.active_job_id == active_job.job_id && !CurrentThread.retry_now

        if will_retry_inline
          job = GoodJob::Job.enqueue(
            active_job,
            scheduled_at: scheduled_at
          )
        elsif will_execute_inline
          job = GoodJob::Job.enqueue(
            active_job,
            scheduled_at: scheduled_at,
            create_with_advisory_lock: true
          )
          InlineBuffer.perform_now_or_defer do
            @capsule.tracker.register do
              perform_inline(job, notify: send_notify?(active_job))
            end
          end
        else
          job = GoodJob::Job.enqueue(
            active_job,
            scheduled_at: scheduled_at
          )

          executed_locally = execute_async? && @capsule&.create_thread(job.job_state)
          Notifier.notify(job.job_state) if !executed_locally && send_notify?(active_job)
        end

        job
      end
    end

    # Shut down the thread pool executors.
    # @param timeout [nil, Numeric, NONE] Seconds to wait for active threads.
    #   * +nil+ trigger a shutdown but not wait for it to complete.
    #   * +-1+ wait until the shutdown is complete.
    #   * +0+ immediately shutdown and stop any threads.
    #   * A positive number will wait that many seconds before stopping any remaining active threads.
    # @return [void]
    def shutdown(timeout: NONE)
      @capsule&.shutdown(timeout: timeout)
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
        (execution_mode.in?([:async, :async_server]) && GoodJob.configuration.in_webserver?)
    end

    # Whether in +:external+ execution mode.
    # @return [Boolean]
    def execute_externally?
      execution_mode.nil? ||
        execution_mode == :external ||
        (execution_mode.in?([:async, :async_server]) && !GoodJob.configuration.in_webserver?)
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

      @capsule.start
      @capsule.lower_thread_priority = true if GoodJob.configuration.lower_thread_priority.in?([true, nil])
      @_async_started = true
    end

    # Whether the async executors are running
    # @return [Boolean]
    def async_started?
      @_async_started
    end

    private

    def send_notify?(active_job)
      return false unless GoodJob.configuration.enable_listen_notify
      return true unless active_job.respond_to?(:good_job_notify)

      !(active_job.good_job_notify == false || (active_job.class.good_job_notify == false && active_job.good_job_notify.nil?))
    end

    # @param job [GoodJob::Job] the job to perform, which must be enqueued and advisory locked already
    # @param notify [Boolean] whether to send a NOTIFY event for a retried job
    def perform_inline(job, notify: true)
      result = nil
      retried_job = nil

      loop do
        result = job.perform(lock_id: @capsule.tracker.id_for_lock)
        retried_job = result.retried_job
        break if retried_job.nil? || retried_job.scheduled_at.nil? || retried_job.scheduled_at > Time.current

        job = retried_job
      end

      Notifier.notify(retried_job.job_state) if notify && retried_job&.scheduled_at && retried_job.scheduled_at > Time.current
      result
    ensure
      job.advisory_unlock
      job.run_callbacks(:perform_unlocked)

      raise result.unhandled_error if result&.unhandled_error
    end
  end
end
