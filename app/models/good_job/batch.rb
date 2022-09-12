# frozen_string_literal: true

module GoodJob
  class Batch < BaseRecord
    include Lockable

    thread_mattr_accessor :current_batch_id
    thread_mattr_accessor :current_batch_callback_id

    self.table_name = 'good_job_batches'

    has_many :executions, class_name: 'GoodJob::Execution', inverse_of: :batch, dependent: nil
    has_many :jobs, class_name: 'GoodJob::Job', inverse_of: :batch, dependent: nil
    has_many :callback_jobs, class_name: 'GoodJob::Job', foreign_key: :batch_callback_id, dependent: nil # rubocop:disable Rails/InverseOf

    scope :finished, -> { where.not(finished_at: nil) }
    scope :discarded, -> { where.not(discarded_at: nil) }
    scope :not_discarded, -> { where(discarded_at: nil) }
    scope :succeeded, -> { finished.not_discarded }

    before_save do
      self.serialized_properties = ActiveJob::Arguments.serialize([properties])
    end

    alias_attribute :enqueued?, :enqueued_at
    alias_attribute :discarded?, :discarded_at
    alias_attribute :finished?, :finished_at

    PROTECTED_PROPERTIES = %i[
      callback_job_class
      callback_queue_name
      callback_priority
      description
    ].freeze

    scope :display_all, (lambda do |after_created_at: nil, after_id: nil|
      query = order(created_at: :desc, id: :desc)
      if after_created_at.present? && after_id.present?
        query = query.where(Arel.sql('(created_at, id) < (:after_created_at, :after_id)'), after_created_at: after_created_at, after_id: after_id)
      elsif after_created_at.present?
        query = query.where(Arel.sql('(after_created_at) < (:after_created_at)'), after_created_at: after_created_at)
      end
      query
    end)

    # Create a new batch and enqueue it
    # @param callback_job_class [String, Object] The class name of the callback job to be enqueued after the batch is finished
    # @param properties [Hash] Additional properties to be stored on the batch
    # @param block [Proc] Enqueue jobs within the block to add them to the batch
    # @return [GoodJob::Batch]
    def self.enqueue(callback_job_class = nil, **properties, &block)
      new.tap do |batch|
        batch.enqueue(callback_job_class, **properties, &block)
      end
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

    def reload
      @_properties = nil
      super
    end

    # Whether the batch has finished and no jobs were discarded
    # @return [Boolean]
    def succeeded?
      !discarded? && finished?
    end

    # Add jobs to the batch
    # @param block [Proc] Enqueue jobs within the block to add them to the batch
    # @return [void]
    def add(&block)
      save
      active_jobs = Bulk.capture(&block)

      begin
        self.class.current_batch_id = id
        Bulk.enqueue(active_jobs)
      ensure
        self.class.current_batch_id = nil
      end
    end

    # Add jobs and (re-)enqueue the batch
    # @param callback_job_class [String, Object] The class name of the callback job to be enqueued after the batch is finished
    # @param properties [Hash] Additional properties to be stored on the batch
    # @param block [Proc] Enqueue jobs within the block to add them to the batch
    # @return [void]
    def enqueue(callback_job_class = nil, **properties, &block)
      properties = properties.dup
      batch_attrs = PROTECTED_PROPERTIES.index_with { |key| properties.delete(key) }.compact
      batch_attrs[:callback_job_class] = callback_job_class if callback_job_class
      batch_attrs[:properties] = self.properties.merge(properties)

      update(batch_attrs)
      add(&block) if block

      self.finished_at = nil
      self.enqueued_at = Time.current if enqueued_at.nil?
      save!

      _continue_discard_or_finish
    end

    def properties=(value)
      @_properties = value
    end

    def properties
      @_properties ||= if serialized_properties.blank?
                         {}
                       else
                         ActiveJob::Arguments.deserialize(serialized_properties).first
                       end
    end

    def display_attributes
      attributes.except('serialized_properties').merge(properties: properties)
    end

    def _continue_discard_or_finish(execution = nil)
      execution_discarded = execution && execution.error.present? && execution.retried_good_job_id.nil?
      with_advisory_lock(function: "pg_advisory_lock") do
        update(discarded_at: Time.current) if execution_discarded && discarded_at.blank?

        if !finished_at && enqueued_at && jobs.where(finished_at: nil).count.zero?
          update(finished_at: Time.current)
          return if callback_job_class.blank?

          callback_job_klass = callback_job_class.constantize
          self.class.within_thread(batch_id: nil, batch_callback_id: id) do
            callback_job_klass.set(priority: callback_priority, queue: callback_queue_name).perform_later(self)
          end
        end
      end
    end
  end
end
