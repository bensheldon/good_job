# frozen_string_literal: true

module GoodJob
  # Deprecated, use +Execution+ instead.
  class DiscreteExecution < Execution
  end

  include ActiveSupport::Deprecation::DeprecatedConstantAccessor

  deprecate_constant :DiscreteExecution, 'Execution', deprecator: GoodJob.deprecator
end
