# frozen_string_literal: true

module GoodJob
  # Created at the time a Job begins executing.
  # Behavior from +DiscreteExecution+ will be merged into this class.
  class Execution < DiscreteExecution
  end
end
