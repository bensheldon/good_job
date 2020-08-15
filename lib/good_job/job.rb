module GoodJob
  class Job < ActiveRecord::Base
    include Lockable

    PreviouslyPerformedError = Class.new(StandardError)

    DEFAULT_QUEUE_NAME = 'default'.freeze
    DEFAULT_PRIORITY = 0

    self.table_name = 'good_jobs'.freeze

    scope :unfinished, (lambda do
      if column_names.include?('finished_at')
        where(finished_at: nil)
      else
        ActiveSupport::Deprecation.warn('GoodJob expects a good_jobs.finished_at column to exist. Please see the GoodJob README.md for migration instructions.')
        nil
      end
    end)
    scope :only_scheduled, -> { where(arel_table['scheduled_at'].lteq(Time.current)).or(where(scheduled_at: nil)) }
    scope :priority_ordered, -> { order('priority DESC NULLS LAST') }
    scope :finished, ->(timestamp = nil) { timestamp ? where(arel_table['finished_at'].lteq(timestamp)) : where.not(finished_at: nil) }
    scope :queue_string, (lambda do |string|
      string = string.presence || '*'

      if string.first == '-'
        exclude_queues = true
        string = string[1..-1]
      end

      queue_names_without_all = string.split(',').map(&:strip).reject { |q| q == '*' }
      return if queue_names_without_all.size.zero?

      if exclude_queues
        where.not(queue_name: queue_names_without_all).or where(queue_name: nil)
      else
        where(queue_name: queue_names_without_all)
      end
    end)

    def self.perform_with_advisory_lock
      good_job = nil
      result = nil
      error = nil

      unfinished.priority_ordered.only_scheduled.limit(1).with_advisory_lock do |good_jobs|
        good_job = good_jobs.first
        break unless good_job

        result, error = good_job.perform
      end

      [good_job, result, error] if good_job
    end

    def self.enqueue(active_job, scheduled_at: nil, create_with_advisory_lock: false)
      good_job = nil
      ActiveSupport::Notifications.instrument("enqueue_job.good_job", { active_job: active_job, scheduled_at: scheduled_at, create_with_advisory_lock: create_with_advisory_lock }) do |instrument_payload|
        good_job = GoodJob::Job.new(
          queue_name: active_job.queue_name.presence || DEFAULT_QUEUE_NAME,
          priority: active_job.priority || DEFAULT_PRIORITY,
          serialized_params: active_job.serialize,
          scheduled_at: scheduled_at || Time.current,
          create_with_advisory_lock: create_with_advisory_lock
        )

        instrument_payload[:good_job] = good_job

        good_job.save!
        active_job.provider_job_id = good_job.id
      end

      good_job
    end

    def perform(destroy_after: !GoodJob.preserve_job_records, reperform_on_standard_error: GoodJob.reperform_jobs_on_standard_error)
      raise PreviouslyPerformedError, 'Cannot perform a job that has already been performed' if finished_at

      GoodJob::CurrentExecution.reset
      result = nil
      rescued_error = nil
      error = nil

      self.performed_at = Time.current
      save! unless destroy_after

      params = serialized_params.merge(
        "provider_job_id" => id
      )

      begin
        ActiveSupport::Notifications.instrument("perform_job.good_job", { good_job: self, process_id: GoodJob::CurrentExecution.process_id, thread_name: GoodJob::CurrentExecution.thread_name }) do
          result = ActiveJob::Base.execute(params)
        end
      rescue StandardError => e
        rescued_error = e
      end

      retry_or_discard_error = GoodJob::CurrentExecution.error_on_retry ||
                               GoodJob::CurrentExecution.error_on_discard

      if rescued_error
        error = rescued_error
      elsif result.is_a?(Exception)
        error = result
        result = nil
      elsif retry_or_discard_error
        error = retry_or_discard_error
      end

      error_message = "#{error.class}: #{error.message}" if error
      self.error = error_message

      if rescued_error && reperform_on_standard_error
        save!
      else
        self.finished_at = Time.current

        if destroy_after
          destroy!
        else
          save!
        end
      end

      [result, error]
    end
  end
end
