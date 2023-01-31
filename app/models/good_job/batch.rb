# frozen_string_literal: true

module GoodJob
  # Note: This class delegates to {GoodJob::BatchRecord} and is intended to be the public interface for Batches.
  class Batch
    include GlobalID::Identification

    delegate(
      :id,
      :created_at,
      :updated_at,
      :persisted?,
      :enqueued_at,
      :finished_at,
      :discarded_at,
      :enqueued?,
      :finished?,
      :succeeded?,
      :discarded?,
      :enqueue,
      :add,
      :description,
      :description=,
      :callback_job_class,
      :callback_job_class=,
      :callback_queue_name,
      :callback_queue_name=,
      :callback_priority,
      :callback_priority=,
      :properties,
      to: :record
    )

    def self.enqueue(callback_job_class = nil, **properties, &block)
      record = GoodJob::BatchRecord.enqueue(callback_job_class, **properties, &block)
      new(_record: record)
    end

    def self.find(id)
      new _record: BatchRecord.find(id)
    end

    def initialize(_record: nil, **attributes)
      @record = _record || BatchRecord.new(**attributes)
    end

    def active_jobs
      record.jobs.map(&:head_execution).map(&:active_job)
    end

    def active_job_callbacks
      record.callback_jobs.map(&:head_execution).map(&:active_job)
    end

    def reload
      @record.reload
    end

    def _record
      record
    end

    private

    def record
      @record
    end
  end
end
