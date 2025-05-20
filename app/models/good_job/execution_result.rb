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
    # @return [Symbol, nil]
    attr_reader :error_event
    # @return [Boolean, nil]
    attr_reader :unexecutable
    # @return [GoodJob::Job, nil]
    attr_reader :retried_job

    # @param value [Object, nil]
    # @param handled_error [Exception, nil]
    # @param unhandled_error [Exception, nil]
    # @param error_event [String, nil]
    # @param unexecutable [Boolean, nil]
    # @param retried_job [GoodJob::Job, nil]
    def initialize(value:, handled_error: nil, unhandled_error: nil, error_event: nil, unexecutable: nil, retried_job: nil)
      @value = value
      @handled_error = handled_error
      @unhandled_error = unhandled_error
      @error_event = error_event
      @unexecutable = unexecutable
      @retried_job = retried_job
    end

    # @return [Boolean]
    def succeeded?
      !(handled_error || unhandled_error || unexecutable || retried?)
    end

    # @return [Boolean]
    def retried?
      retried_job.present?
    end
  end
end
