# frozen_string_literal: true

module GoodJob
  # Active Record model to share behavior between {Job} and {Execution} models
  # which both read out of the same table.
  class BaseExecution < BaseRecord
    include AdvisoryLockable
    include ErrorEvents
    include Filterable
    include Reportable

    self.table_name = 'good_jobs'

    # With a given class name
    # @!method job_class(name)
    # @!scope class
    # @param name [String] Execution class name
    # @return [ActiveRecord::Relation]
    scope :job_class, ->(name) { where(params_job_class.eq(name)) }

    class << self
      def json_string(json, attr)
        Arel::Nodes::Grouping.new(Arel::Nodes::InfixOperation.new('->>', json, Arel::Nodes.build_quoted(attr)))
      end

      def params_job_class
        json_string(arel_table['serialized_params'], 'job_class')
      end

      def params_execution_count
        Arel::Nodes::InfixOperation.new(
          '::',
          json_string(arel_table['serialized_params'], 'executions'),
          Arel.sql('integer')
        )
      end

      def coalesce_scheduled_at_created_at
        arel_table.coalesce(arel_table['scheduled_at'], arel_table['created_at'])
      end

      def discrete_support?
        GoodJob::DiscreteExecution.migrated?
      end

      def error_event_migrated?
        return true if columns_hash["error_event"].present?

        migration_pending_warning!
        false
      end

      def cron_indices_migrated?
        return true if connection.index_name_exists?(:good_jobs, :index_good_jobs_on_cron_key_and_created_at_cond)

        migration_pending_warning!
        false
      end

      def labels_migrated?
        return true if columns_hash["labels"].present?

        migration_pending_warning!
        false
      end

      def labels_indices_migrated?
        return true if connection.index_name_exists?(:good_jobs, :index_good_jobs_on_labels)

        migration_pending_warning!
        false
      end

      def active_job_id_index_removal_migrated?
        return true unless connection.index_name_exists?(:good_jobs, :index_good_jobs_on_active_job_id)

        migration_pending_warning!
        false
      end

      def candidate_lookup_index_migrated?
        return true if connection.index_name_exists?(:good_jobs, :index_good_job_jobs_for_candidate_lookup)

        migration_pending_warning!
        false
      end
    end

    # The ActiveJob job class, as a string
    # @return [String]
    def job_class
      discrete? ? attributes['job_class'] : serialized_params['job_class']
    end

    def discrete?
      self.class.discrete_support? && is_discrete?
    end

    # Build an ActiveJob instance and deserialize the arguments, using `#active_job_data`.
    #
    # @param ignore_deserialization_errors [Boolean]
    #   Whether to ignore ActiveJob::DeserializationError and NameError when deserializing the arguments.
    #   This is most useful if you aren't planning to use the arguments directly.
    def active_job(ignore_deserialization_errors: false)
      ActiveJob::Base.deserialize(active_job_data).tap do |aj|
        aj.send(:deserialize_arguments_if_needed)
      end
    rescue ActiveJob::DeserializationError, NameError
      raise unless ignore_deserialization_errors
    end

    private

    def active_job_data
      serialized_params.deep_dup
                       .tap do |job_data|
        job_data["provider_job_id"] = id
        job_data["good_job_concurrency_key"] = concurrency_key if concurrency_key
        job_data["good_job_labels"] = Array(labels) if self.class.labels_migrated? && labels.present?
      end
    end
  end
end
