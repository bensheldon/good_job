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
    # @return [Exception, nil]
    attr_reader :unexecutable
    # @return [Exception, nil]
    attr_reader :retried
    alias retried? retried

    # @param value [Object, nil]
    # @param handled_error [Exception, nil]
    # @param unhandled_error [Exception, nil]
    # @param executable [Boolean, nil]
    # @param retried [Boolean, nil]
    def initialize(value:, handled_error: nil, unhandled_error: nil, unexecutable: nil, retried: false)
      @value = value
      @handled_error = handled_error
      @unhandled_error = unhandled_error
      @unexecutable = unexecutable
      @retried = retried
    end

    def succeeded?
      !(handled_error || unhandled_error || unexecutable || retried)
    end
  end
end
