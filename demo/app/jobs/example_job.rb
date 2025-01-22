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

  retry_on(DeadError, attempts: 3) { nil }

  class BatchJob < ApplicationJob
    class CallbackJob < ApplicationJob
      def perform(batch, params)
      end
    end
    def perform
      GoodJob::Batch.enqueue(on_finish: CallbackJob, description: "Example batch", foo: "bar") do
        3.times do
          job_type = TYPES.sample
          ExampleJob.set(good_job_labels: [job_type]).perform_later(job_type)
        end
      end
    end
  end

  class BatchCallbackJob < ApplicationJob
    def perform(batch, params)
      nil
    end
  end

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
      50.times do
        break if blocking_reload? || GoodJob.current_thread_shutting_down?
        sleep 0.1
      end
    end
  end

  private

  def blocking_reload?
    return false if Rails.application.config.cache_classes

    ActiveSupport::Dependencies.interlock.raw_state do |threads|
      # Find any thread attempting to unload (reload) code
      return unless threads.any? { |_, info| info[:purpose] == :unload }

      # Is the current thread blocking it? Likely yes.
      info = threads[Thread.current]
      info[:sharing] > 0 || # Thread holds a share lock
        (info[:exclusive] && ![:load, :unload].include?(info[:purpose])) # Or holds incompatible exclusive lock
    end
  end
end
