# frozen_string_literal: true

module GoodJob
  # @!visibility private
  # Periodically writes the progress of a performing Active Job continuation
  # (+ActiveJob::Continuable+) to its job record, so that if the process exits
  # without a graceful shutdown (e.g. +SIGKILL+ or running out of memory), the
  # job resumes from a recent checkpoint rather than from its last graceful
  # interruption. Work done after the last write is performed again, so each
  # unit of work must be idempotent.
  #
  # Active Job calls +queue_adapter.stopping?+ only at checkpoints, where the
  # step's cursor is consistent, and Rails (via Active Record's railtie) raises
  # +ActiveJob::Continuation::CheckpointError+ from a checkpoint inside an open
  # transaction on any database. The write is therefore never part of the job's
  # own transaction; to be safe, it is also skipped if GoodJob's connection has
  # an open transaction.
  #
  # An instance is scoped to a single job execution and is not thread-safe.
  class ContinuationProgressWriter
    # Intervals are randomly lengthened by up to this proportion, so that jobs that
    # started together (e.g. after a deploy) don't keep writing in lockstep.
    JITTER = 0.15
    # Keys of serialized job data that record continuation progress.
    PROGRESS_KEYS = %w[continuation resumptions attributes].freeze
    private_constant :JITTER, :PROGRESS_KEYS

    # @param job [GoodJob::Job] the job record being performed
    def initialize(job)
      @job = job
      interval = interval_for(job.job_class&.safe_constantize)
      # +nil+ when periodic writes are disabled or the job is no longer owned by this execution
      @throttled_writer = ThrottledBlock.new(interval, jitter: JITTER) { |active_job| write(active_job) } if interval
    end

    # Writes the progress of the Active Job continuation if a write is due.
    # @param active_job [ActiveJob::Base] the job passed to +queue_adapter.stopping?+
    # @return [Boolean, nil] +true+ if progress was written, +false+ if a write was
    #   attempted but did not happen, or +nil+ if no write was due or applicable
    def write_if_due(active_job)
      return unless active_job.respond_to?(:continuation) && active_job.job_id == @job.active_job_id

      @throttled_writer&.call(active_job)
    end

    private

    # @return [Boolean] whether progress was written
    def write(active_job)
      return false if @job.class.connection_pool.with_connection(&:transaction_open?)

      ActiveSupport::Notifications.instrument("continuation_progress.good_job", { job: @job, active_job: active_job }) do |payload|
        progress = active_job.serialize.slice(*PROGRESS_KEYS)
        # Only update the record while this execution still owns it, so that an
        # execution that has lost the job cannot overwrite a newer execution's progress.
        updated = @job.class.where(id: @job.id, finished_at: nil, executions_count: @job.executions_count)
                      .update_all(["serialized_params = serialized_params || ?::jsonb", progress.to_json]) # rubocop:disable Rails/SkipsModelValidations

        payload[:lost_ownership] = updated.zero?
        if payload[:lost_ownership]
          @throttled_writer = nil
          next false
        end

        @job.serialized_params = @job.serialized_params.merge(progress.as_json)
        @job.clear_attribute_changes([:serialized_params])
        true
      end
    rescue StandardError => e
      GoodJob._on_thread_error(e)
      false
    end

    def interval_for(job_class)
      value = job_class.good_job_continuation_progress_interval if job_class.respond_to?(:good_job_continuation_progress_interval)
      if value.nil?
        GoodJob.configuration.continuation_progress_interval
      elsif value.present? && value.to_f.positive?
        value.to_f
      end
    end
  end
end
