# frozen_string_literal: true

require 'active_job/arguments'

module GoodJob
  class BatchRecord < BaseRecord
    include AdvisoryLockable
    include Filterable

    self.table_name = 'good_job_batches'
    self.implicit_order_column = 'created_at'

    has_many :jobs, class_name: 'GoodJob::Job', inverse_of: :batch, foreign_key: :batch_id, dependent: nil
    has_many :executions, class_name: 'GoodJob::Execution', foreign_key: :batch_id, inverse_of: :batch, dependent: nil
    has_many :callback_jobs, class_name: 'GoodJob::Job', foreign_key: :batch_callback_id, dependent: nil # rubocop:disable Rails/InverseOf

    scope :finished, -> { where.not(finished_at: nil) }
    scope :discarded, -> { where.not(discarded_at: nil) }
    scope :not_discarded, -> { where(discarded_at: nil) }
    scope :succeeded, -> { finished.not_discarded }

    scope :finished_before, ->(timestamp) { where(arel_table['finished_at'].lteq(bind_value('finished_at', timestamp, ActiveRecord::Type::DateTime))) }

    alias_attribute :enqueued?, :enqueued_at
    alias_attribute :discarded?, :discarded_at
    alias_attribute :finished?, :finished_at

    def self.jobs_finished_at_migrated?
      column_names.include?('jobs_finished_at')
    end

    # Whether the batch has finished and no jobs were discarded
    # @return [Boolean]
    def succeeded?
      !discarded? && finished?
    end

    def to_batch
      Batch.new(_record: self)
    end

    def display_attributes
      display_properties = begin
        serialized_properties
      rescue ActiveJob::DeserializationError
        JSON.parse(read_attribute_before_type_cast(:serialized_properties))
      end

      attribute_names.to_h do |name|
        if name == "serialized_properties"
          ["properties", display_properties]
        else
          [name, self[name]]
        end
      end
    end

    def _continue_discard_or_finish(job = nil, lock: true)
      job_discarded = job && job.finished_at.present? && job.error.present?
      buffer = GoodJob::Adapter::InlineBuffer.capture do
        advisory_lock_maybe(lock) do
          reload

          if job_discarded && !discarded_at
            update(discarded_at: Time.current)

            if on_discard.present?
              discard_job_class = on_discard.constantize
              Job.defer_after_commit_maybe(discard_job_class) do
                Batch.within_thread(batch_id: nil, batch_callback_id: id) do
                  discard_job_class.set(priority: callback_priority, queue: callback_queue_name).perform_later(to_batch, { event: :discard })
                end
              end
            end
          end

          if enqueued_at && !(self.class.jobs_finished_at_migrated? ? jobs_finished_at : finished_at) && jobs.where(finished_at: nil).none?
            self.class.jobs_finished_at_migrated? ? update(jobs_finished_at: Time.current) : update(finished_at: Time.current)

            if !discarded_at && on_success.present?
              success_job_class = on_success.constantize
              Job.defer_after_commit_maybe(success_job_class) do
                Batch.within_thread(batch_id: nil, batch_callback_id: id) do
                  success_job_class.set(priority: callback_priority, queue: callback_queue_name).perform_later(to_batch, { event: :success })
                end
              end
            end

            if on_finish.present?
              finish_job_class = on_finish.constantize
              Job.defer_after_commit_maybe(finish_job_class) do
                Batch.within_thread(batch_id: nil, batch_callback_id: id) do
                  on_finish.constantize.set(priority: callback_priority, queue: callback_queue_name).perform_later(to_batch, { event: :finish })
                end
              end
            end
          end

          update(finished_at: Time.current) if !finished_at && self.class.jobs_finished_at_migrated? && jobs_finished? && callback_jobs.where(finished_at: nil).none?
        end
      end

      buffer.call
    end

    class PropertySerializer
      def self.dump(value)
        ActiveJob::Arguments.serialize([value]).first
      end

      def self.load(value)
        ActiveJob::Arguments.deserialize([value]).first
      end
    end

    if Rails.gem_version < Gem::Version.new('7.1.0.alpha')
      serialize :serialized_properties, PropertySerializer, default: -> { {} }
    else
      serialize :serialized_properties, coder: PropertySerializer, default: -> { {} }
    end
    alias_attribute :properties, :serialized_properties

    def properties=(value)
      raise ArgumentError, "Properties must be a Hash" unless value.is_a?(Hash)

      self.serialized_properties = value
    end

    def jobs_finished?
      self.class.jobs_finished_at_migrated? ? jobs_finished_at : finished_at
    end

    def jobs_finished_at
      self.class.jobs_finished_at_migrated? ? self[:jobs_finished_at] : self[:finished_at]
    end

    private

    def advisory_lock_maybe(value, &block)
      if value
        transaction { with_advisory_lock(function: "pg_advisory_xact_lock", &block) }
      else
        yield
      end
    end
  end
end

ActiveSupport.run_load_hooks(:good_job_batch_record, GoodJob::BatchRecord)
