# frozen_string_literal: true

module GoodJob
  # ActiveRecord model that represents an +ActiveJob+ job.
  class Execution < BaseExecution
    # ActiveJob jobs without a +queue_name+ attribute are placed on this queue.
    DEFAULT_QUEUE_NAME = 'default'
    # ActiveJob jobs without a +priority+ attribute are given this priority.
    DEFAULT_PRIORITY = 0

    self.table_name = 'good_jobs'
    self.advisory_lockable_column = 'active_job_id'

    belongs_to :batch, class_name: 'GoodJob::BatchRecord', optional: true, inverse_of: :executions
    belongs_to :job, class_name: 'GoodJob::Job', foreign_key: 'active_job_id', primary_key: 'active_job_id', optional: true, inverse_of: :executions
    has_many :discrete_executions, class_name: 'GoodJob::DiscreteExecution', foreign_key: 'active_job_id', primary_key: 'active_job_id', inverse_of: :execution # rubocop:disable Rails/HasManyOrHasOneDependent

    after_destroy lambda {
      GoodJob::DiscreteExecution.where(active_job_id: active_job_id).delete_all if discrete? # TODO: move into association `dependent: :delete_all` after v4
      self.class.active_job_id(active_job_id).delete_all
    }, if: -> { @_destroy_job }

    # Get executions with given ActiveJob ID
    # @!method active_job_id(active_job_id)
    # @!scope class
    # @param active_job_id [String]
    #   ActiveJob ID
    # @return [ActiveRecord::Relation]
    scope :active_job_id, ->(active_job_id) { where(active_job_id: active_job_id) }

    # Get Jobs were completed before the given timestamp. If no timestamp is
    # provided, get all jobs that have been completed. By default, GoodJob
    # destroys jobs after they are completed and this will find no jobs.
    # However, if you have changed {GoodJob.preserve_job_records}, this may
    # find completed Jobs.
    # @!method finished(timestamp = nil)
    # @!scope class
    # @param timestamp (Float)
    #   Get jobs that finished before this time (in epoch time).
    # @return [ActiveRecord::Relation]
    scope :finished, ->(timestamp = nil) { timestamp ? where(arel_table['finished_at'].lteq(timestamp)) : where.not(finished_at: nil) }

    # Get Jobs that started but not finished yet.
    # @!method running
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :running, -> { where.not(performed_at: nil).where(finished_at: nil) }

    # Get Jobs that do not have subsequent retries
    # @!method running
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :head, -> { where(retried_good_job_id: nil) }

    # Get Jobs have errored that will not be retried further
    # @!method running
    # @!scope class
    # @return [ActiveRecord::Relation]
    scope :dead, -> { head.where.not(error: nil) }

    def self.build_for_enqueue(active_job, overrides = {})
      new(**enqueue_args(active_job, overrides))
    end

    # Construct arguments for GoodJob::Execution from an ActiveJob instance.
    def self.enqueue_args(active_job, overrides = {})
      if active_job.priority && GoodJob.configuration.smaller_number_is_higher_priority.nil?
        GoodJob.deprecator.warn(<<~DEPRECATION)
          The next major version of GoodJob (v4.0) will change job `priority` to give smaller numbers higher priority (default: `0`), in accordance with Active Job's definition of priority.
            To opt-in to this behavior now, set `config.good_job.smaller_number_is_higher_priority = true` in your GoodJob initializer or application.rb.
            To not opt-in yet, but silence this deprecation warning, set `config.good_job.smaller_number_is_higher_priority = false`.
        DEPRECATION
      end

      execution_args = {
        active_job_id: active_job.job_id,
        queue_name: active_job.queue_name.presence || DEFAULT_QUEUE_NAME,
        priority: active_job.priority || DEFAULT_PRIORITY,
        serialized_params: active_job.serialize,
      }
      execution_args[:scheduled_at] = Time.zone.at(active_job.scheduled_at) if active_job.scheduled_at
      execution_args[:concurrency_key] = active_job.good_job_concurrency_key if active_job.respond_to?(:good_job_concurrency_key)

      reenqueued_current_execution = CurrentThread.active_job_id && CurrentThread.active_job_id == active_job.job_id
      current_execution = CurrentThread.execution

      if reenqueued_current_execution
        if GoodJob::BatchRecord.migrated?
          execution_args[:batch_id] = current_execution.batch_id
          execution_args[:batch_callback_id] = current_execution.batch_callback_id
        end
        execution_args[:cron_key] = current_execution.cron_key
      else
        if GoodJob::BatchRecord.migrated?
          execution_args[:batch_id] = GoodJob::Batch.current_batch_id
          execution_args[:batch_callback_id] = GoodJob::Batch.current_batch_callback_id
        end
        execution_args[:cron_key] = CurrentThread.cron_key
        execution_args[:cron_at] = CurrentThread.cron_at
      end

      execution_args.merge(overrides)
    end

    # Finds the next eligible Execution, acquire an advisory lock related to it, and
    # executes the job.
    # @return [ExecutionResult, nil]
    #   If a job was executed, returns an array with the {Execution} record, the
    #   return value for the job's +#perform+ method, and the exception the job
    #   raised, if any (if the job raised, then the second array entry will be
    #   +nil+). If there were no jobs to execute, returns +nil+.
    def self.perform_with_advisory_lock(parsed_queues: nil, queue_select_limit: nil, capsule: GoodJob.capsule)
      execution = nil
      result = nil
      unfinished.dequeueing_ordered(parsed_queues).only_scheduled.limit(1).with_advisory_lock(unlock_session: true, select_limit: queue_select_limit) do |executions|
        execution = executions.first
        break if execution.blank?

        unless execution.executable?
          result = ExecutionResult.new(value: nil, unexecutable: true)
          break
        end

        yield(execution) if block_given?
        capsule.tracker.register do
          result = execution.perform(id_for_lock: capsule.tracker.id_for_lock)
        end
      end
      execution&.run_callbacks(:perform_unlocked)

      result
    end

    # Places an ActiveJob job on a queue by creating a new {Execution} record.
    # @param active_job [ActiveJob::Base]
    #   The job to enqueue.
    # @param scheduled_at [Float]
    #   Epoch timestamp when the job should be executed, if blank will delegate to the ActiveJob instance
    # @param create_with_advisory_lock [Boolean]
    #   Whether to establish a lock on the {Execution} record after it is created.
    # @return [Execution]
    #   The new {Execution} instance representing the queued ActiveJob job.
    def self.enqueue(active_job, scheduled_at: nil, create_with_advisory_lock: false)
      ActiveSupport::Notifications.instrument("enqueue_job.good_job", { active_job: active_job, scheduled_at: scheduled_at, create_with_advisory_lock: create_with_advisory_lock }) do |instrument_payload|
        current_execution = CurrentThread.execution

        retried = current_execution && current_execution.active_job_id == active_job.job_id
        if retried
          if current_execution.discrete?
            execution = current_execution
            execution.assign_attributes(enqueue_args(active_job, { scheduled_at: scheduled_at }))
            execution.scheduled_at ||= Time.current
            # TODO: these values ideally shouldn't be persisted until the current_execution is finished
            #   which will require handling `retry_job` being called from outside the execution context.
            execution.performed_at = nil
            execution.finished_at = nil
          else
            execution = build_for_enqueue(active_job, { scheduled_at: scheduled_at })
          end
        else
          execution = build_for_enqueue(active_job, { scheduled_at: scheduled_at })
          execution.make_discrete if discrete_support?
        end

        if create_with_advisory_lock
          if execution.persisted?
            execution.advisory_lock
          else
            execution.create_with_advisory_lock = true
          end
        end

        instrument_payload[:execution] = execution
        execution.save!

        if retried
          CurrentThread.execution_retried = true
          CurrentThread.execution.retried_good_job_id = execution.id unless current_execution.discrete?
        end

        active_job.provider_job_id = execution.id
        execution
      end
    end

    # Tests whether this job is safe to be executed by this thread.
    # @return [Boolean]
    def executable?
      self.class.unscoped.unfinished.owns_advisory_locked.exists?(id: id)
    end

    def make_discrete
      self.is_discrete = true
      self.id = active_job_id
      self.job_class = serialized_params['job_class']
      self.executions_count ||= 0

      current_time = Time.current
      self.created_at ||= current_time
      self.scheduled_at ||= current_time
    end

    # Return formatted serialized_params for display in the dashboard
    # @return [Hash]
    def display_serialized_params
      serialized_params.merge({
                                _good_job: attributes.except('serialized_params', 'locktype', 'owns_advisory_lock'),
                              })
    end

    def running?
      if has_attribute?(:locktype)
        self['locktype'].present?
      else
        advisory_locked?
      end
    end

    def number
      serialized_params.fetch('executions', 0) + 1
    end

    # Time between when this job was expected to run and when it started running
    def queue_latency
      now = Time.zone.now
      expected_start = scheduled_at || created_at
      actual_start = performed_at || finished_at || now

      actual_start - expected_start unless expected_start >= now
    end

    # Time between when this job started and finished
    def runtime_latency
      (finished_at || Time.zone.now) - performed_at if performed_at
    end
  end
end
