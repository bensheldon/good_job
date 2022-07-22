# frozen_string_literal: true
module GoodJob
  # Stores the results of job execution
  class ExecutionResult
    # @return [Object, nil]
    attr_reader :value
    # @return [Exception, nil]
    attr_reader :handled_error
    # @return [Exception, nil]
    attr_reader :unhandled_error

    # @param value [Object, nil]
    # @param handled_error [Exception, nil]
    # @param unhandled_error [Exception, nil]
    def initialize(value:, handled_error: nil, unhandled_error: nil)
      @value = value
      @handled_error = handled_error
      @unhandled_error = unhandled_error
    end
  end
end
