# frozen_string_literal: true

module GoodJob
  module ActiveJobExtensions
    module Labels
      extend ActiveSupport::Concern

      module Prepends
        def enqueue(options = {})
          self.good_job_labels = _good_job_with_applied_labels(Array(options[:good_job_labels])) if options.key?(:good_job_labels)
          super
        end

        def deserialize(job_data)
          super
          self.good_job_labels = job_data.delete("good_job_labels")&.dup || []
        end

        private

        # Class-level labels may be Lambdas/Procs, invoked in the context of the job.
        def _good_job_default_labels
          labels = Array(self.class.good_job_labels).filter_map do |label|
            label.respond_to?(:call) ? instance_exec(&label) : label
          end
          _good_job_with_applied_labels(labels)
        end

        def _good_job_with_applied_labels(labels)
          return labels unless self.class.respond_to?(:good_job_concurrency_rules)

          applied_labels = Array(self.class.good_job_concurrency_rules).filter_map { |rule| rule.applied_label(self) }
          (labels + applied_labels).uniq
        end
      end

      included do
        prepend Prepends

        class_attribute :good_job_labels, instance_accessor: false, instance_predicate: false, default: []
        attr_writer :good_job_labels
      end

      # Default labels are resolved on first read rather than when the job is initialized,
      # because Active Job initializes jobs without their arguments when deserializing them.
      # @return [Array]
      def good_job_labels
        @good_job_labels = _good_job_default_labels if @good_job_labels.nil?
        @good_job_labels
      end
    end
  end
end
