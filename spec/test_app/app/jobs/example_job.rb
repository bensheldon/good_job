class ExampleJob < ApplicationJob
  ExpectedError = Class.new(StandardError)
  DeadError = Class.new(StandardError)

  TYPES = [
    SUCCESS_TYPE = 'success',
    ERROR_ONCE_TYPE = 'error_once',
    ERROR_FIVE_TIMES_TYPE = 'error_five_times',
    DEAD_TYPE = 'dead',
    SLOW_TYPE = 'slow',
  ]
  
  retry_on DeadError, attempts: 3

  def perform(type = SUCCESS_TYPE)
    if type == SUCCESS_TYPE
      true
    elsif type == ERROR_ONCE_TYPE
      raise(ExpectedError, "Executed #{executions} #{"time".pluralize(executions)}.") if executions < 2
    elsif type == ERROR_FIVE_TIMES_TYPE
      raise(ExpectedError, "Executed #{executions} #{"time".pluralize(executions)}.") if executions < 6
    elsif type == DEAD_TYPE
      raise DeadError
    elsif type == SLOW_TYPE
      sleep 5
    end
  end
end
