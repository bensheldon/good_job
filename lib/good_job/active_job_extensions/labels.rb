# frozen_string_literal: true

module GoodJob
  module ActiveJobExtensions
    module Labels
      extend ActiveSupport::Concern

      module Prepends
        def initialize(...)
          super
          # Class-level labels may be Lambdas/Procs, invoked in the context of the job
          self.good_job_labels = Array(self.class.good_job_labels).filter_map do |label|
            label.respond_to?(:call) ? instance_exec(&label) : label
          end
        end

        def enqueue(options = {})
          self.good_job_labels = Array(options[:good_job_labels]) if options.key?(:good_job_labels)
          super
        end

        def deserialize(job_data)
          super
          self.good_job_labels = job_data.delete("good_job_labels")&.dup || []
        end
      end

      included do
        prepend Prepends

        class_attribute :good_job_labels, instance_accessor: false, instance_predicate: false, default: []
        attr_accessor :good_job_labels
      end
    end
  end
end
