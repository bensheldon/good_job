# frozen_string_literal: true

module GoodJob
  # NOTE: This class delegates to {GoodJob::BatchRecord} and is intended to be the public interface for Batches.
  class Batch
    include GlobalID::Identification

    thread_cattr_accessor :current_batch_id
    thread_cattr_accessor :current_batch_callback_id

    PROTECTED_PROPERTIES = %i[
      on_finish
      on_success
      on_discard
      callback_queue_name
      callback_priority
      description
      properties
    ].freeze

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
      :description,
      :description=,
      :on_finish,
      :on_finish=,
      :on_success,
      :on_success=,
      :on_discard,
      :on_discard=,
      :callback_queue_name,
      :callback_queue_name=,
      :callback_priority,
      :callback_priority=,
      :properties,
      :properties=,
      :save,
      :reload,
      to: :record
    )

    # Create a new batch and enqueue it
    # @param properties [Hash] Additional properties to be stored on the batch
    # @param block [Proc] Enqueue jobs within the block to add them to the batch
    # @return [GoodJob::BatchRecord]
    def self.enqueue(active_jobs = [], **properties, &block)
      new.tap do |batch|
        batch.enqueue(active_jobs, **properties, &block)
      end
    end

    def self.primary_key
      :id
    end

    def self.find(id)
      new _record: BatchRecord.find(id)
    end

    # Helper method to enqueue jobs and assign them to a batch
    def self.within_thread(batch_id: nil, batch_callback_id: nil)
      original_batch_id = current_batch_id
      original_batch_callback_id = current_batch_callback_id

      self.current_batch_id = batch_id
      self.current_batch_callback_id = batch_callback_id

      yield
    ensure
      self.current_batch_id = original_batch_id
      self.current_batch_callback_id = original_batch_callback_id
    end

    def initialize(_record: nil, **properties) # rubocop:disable Lint/UnderscorePrefixedVariableName
      self.record = _record || BatchRecord.new
      assign_properties(properties)
    end

    # @return [Array<ActiveJob::Base>] Active jobs added to the batch
    def enqueue(active_jobs = [], **properties, &block)
      assign_properties(properties)
      if record.new_record?
        record.save!
      else
        record.with_advisory_lock(function: "pg_advisory_lock") do
          record.enqueued_at_will_change!
          record.finished_at_will_change!
          record.update!(enqueued_at: nil, finished_at: nil)
        end
      end

      active_jobs = add(active_jobs, &block)

      Rails.application.executor.wrap do
        record.with_advisory_lock(function: "pg_advisory_lock") do
          record.update!(enqueued_at: Time.current)

          # During inline execution, this could enqueue and execute further jobs
          record._continue_discard_or_finish(lock: false)
        end
      end

      active_jobs
    end

    # Enqueue jobs and add them to the batch
    # @param block [Proc] Enqueue jobs within the block to add them to the batch
    # @return [Array<ActiveJob::Base>] Active jobs added to the batch
    def add(active_jobs = nil, &block)
      record.save if record.new_record?

      buffer = Bulk::Buffer.new
      buffer.add(active_jobs)
      buffer.capture(&block) if block

      self.class.within_thread(batch_id: id) do
        buffer.enqueue
      end

      buffer.active_jobs
    end

    def active_jobs
      record.jobs.map(&:active_job)
    end

    def callback_active_jobs
      record.callback_jobs.map(&:active_job)
    end

    def assign_properties(properties)
      properties = properties.dup
      batch_attrs = PROTECTED_PROPERTIES.index_with { |key| properties.delete(key) }.compact
      record.assign_attributes(batch_attrs)
      self.properties.merge!(properties)
    end

    def _record
      record
    end

    private

    attr_accessor :record
  end
end
