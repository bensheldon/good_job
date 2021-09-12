class ExampleJob < ApplicationJob
  ExpectedError = Class.new(StandardError)
  DeadError = Class.new(StandardError)

  retry_on DeadError, attempts: 3

  def perform(type = :success)
    type = type.to_sym

    if type == :success
      true
    elsif type == :error_once
      raise(ExpectedError, "Executed #{executions} #{"time".pluralize(executions)}.") if executions < 2
    elsif type == :error_five_times
      raise(ExpectedError, "Executed #{executions} #{"time".pluralize(executions)}.") if executions < 6
    elsif type == :dead
      raise DeadError
    end
  end
end
