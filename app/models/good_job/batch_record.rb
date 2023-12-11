# frozen_string_literal: true

require 'active_job/arguments'

module GoodJob
  class BatchRecord < BaseRecord
    include AdvisoryLockable

    self.table_name = 'good_job_batches'

    has_many :jobs, class_name: 'GoodJob::Job', inverse_of: :batch, foreign_key: :batch_id, dependent: nil
    has_many :executions, class_name: 'GoodJob::Execution', foreign_key: :batch_id, inverse_of: :batch, dependent: nil
    has_many :callback_jobs, class_name: 'GoodJob::Job', foreign_key: :batch_callback_id, dependent: nil # rubocop:disable Rails/InverseOf

    scope :finished, -> { where.not(finished_at: nil) }
    scope :discarded, -> { where.not(discarded_at: nil) }
    scope :not_discarded, -> { where(discarded_at: nil) }
    scope :succeeded, -> { finished.not_discarded }

    alias_attribute :enqueued?, :enqueued_at
    alias_attribute :discarded?, :discarded_at
    alias_attribute :finished?, :finished_at

    scope :display_all, (lambda do |after_created_at: nil, after_id: nil|
      query = order(created_at: :desc, id: :desc)
      if after_created_at.present? && after_id.present?
        query = query.where(Arel.sql('(created_at, id) < (:after_created_at, :after_id)'), after_created_at: after_created_at, after_id: after_id)
      elsif after_created_at.present?
        query = query.where(Arel.sql('(after_created_at) < (:after_created_at)'), after_created_at: after_created_at)
      end
      query
    end)

    # Whether the batch has finished and no jobs were discarded
    # @return [Boolean]
    def succeeded?
      !discarded? && finished?
    end

    def to_batch
      Batch.new(_record: self)
    end

    def display_attributes
      attributes.except('serialized_properties').merge(properties: properties)
    end

    def _continue_discard_or_finish(execution = nil, lock: true)
      execution_discarded = execution && execution.error.present? && execution.retried_good_job_id.nil?
      take_advisory_lock(lock) do
        Batch.within_thread(batch_id: nil, batch_callback_id: id) do
          reload
          if execution_discarded && !discarded_at
            update(discarded_at: Time.current)
            on_discard.constantize.set(priority: callback_priority, queue: callback_queue_name).perform_later(to_batch, { event: :discard }) if on_discard.present?
          end

          if enqueued_at && !finished_at && jobs.where(finished_at: nil).count.zero?
            update(finished_at: Time.current)
            on_success.constantize.set(priority: callback_priority, queue: callback_queue_name).perform_later(to_batch, { event: :success }) if !discarded_at && on_success.present?
            on_finish.constantize.set(priority: callback_priority, queue: callback_queue_name).perform_later(to_batch, { event: :finish }) if on_finish.present?
          end
        end
      end
    end

    class PropertySerializer
      def self.dump(value)
        ActiveJob::Arguments.serialize([value]).first
      end

      def self.load(value)
        ActiveJob::Arguments.deserialize([value]).first
      end
    end

    if Rails.gem_version < Gem::Version.new('6.1.0.alpha')
      # serialize does not yet take a default value, must set via Attributes API
      attribute :serialized_properties, :json, default: -> { {} }
      serialize :serialized_properties, PropertySerializer
    elsif Rails.gem_version < Gem::Version.new('7.1.0.alpha')
      serialize :serialized_properties, PropertySerializer, default: -> { {} }
    else
      serialize :serialized_properties, coder: PropertySerializer, default: -> { {} }
    end
    alias_attribute :properties, :serialized_properties

    def properties=(value)
      raise ArgumentError, "Properties must be a Hash" unless value.is_a?(Hash)

      self.serialized_properties = value
    end

    private

    def take_advisory_lock(value, &block)
      if value
        with_advisory_lock(function: "pg_advisory_lock", &block)
      else
        yield
      end
    end
  end
end
