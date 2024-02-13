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
    # @return [String, nil]
    attr_reader :error_event
    # @return [Boolean, nil]
    attr_reader :unexecutable
    # @return [GoodJob::Execution, nil]
    attr_reader :retried

    # @param value [Object, nil]
    # @param handled_error [Exception, nil]
    # @param unhandled_error [Exception, nil]
    # @param error_event [String, nil]
    # @param unexecutable [Boolean, nil]
    # @param retried [Boolean, nil]
    def initialize(value:, handled_error: nil, unhandled_error: nil, error_event: nil, unexecutable: nil, retried: nil)
      @value = value
      @handled_error = handled_error
      @unhandled_error = unhandled_error
      @error_event = error_event
      @unexecutable = unexecutable
      @retried = retried
    end

    # @return [Boolean]
    def succeeded?
      !(handled_error || unhandled_error || unexecutable || retried?)
    end

    # @return [Boolean]
    def retried?
      retried.present?
    end
  end
end
