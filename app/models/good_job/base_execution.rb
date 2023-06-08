# frozen_string_literal: true

module GoodJob
  # ActiveRecord model to share behavior between {Job} and {Execution} models
  # which both read out of the same table.
  class BaseExecution < BaseRecord
    self.table_name = 'good_jobs'

    # With a given class name
    # @!method job_class
    # @!scope class
    # @param string [String] Execution class name
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
        if connection.table_exists?(GoodJob::DiscreteExecution.table_name)
          true
        else
          migration_pending_warning!
          false
        end
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
  end
end
