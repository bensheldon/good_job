# frozen_string_literal: true

module GoodJob
  module ActiveJobExtensions
    module InterruptErrors
      extend ActiveSupport::Concern

      included do
        around_perform do |_job, block|
          raise InterruptError, "Interrupted after starting perform at '#{CurrentThread.execution_interrupted}'" if CurrentThread.execution_interrupted.present?

          block.call
        end
      end
    end
  end
end
