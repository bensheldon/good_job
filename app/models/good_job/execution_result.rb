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
    attr_reader :unlocked_error
    # @return [Exception, nil]
    attr_reader :retried
    alias retried? retried

    # @param value [Object, nil]
    # @param handled_error [Exception, nil]
    # @param unhandled_error [Exception, nil]
    def initialize(value:, handled_error: nil, unhandled_error: nil, unlocked_error: nil, retried: false)
      @value = value
      @handled_error = handled_error
      @unhandled_error = unhandled_error
      @unlocked_error = unlocked_error
      @retried = retried
    end

    def succeeded?
      !(handled_error || unhandled_error || unlocked_error || retried)
    end
  end
end
