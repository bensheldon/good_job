module GoodJob
  # Delegates the interface of a single {Scheduler} to multiple Schedulers.
  class MultiScheduler
    # @return [Array<Scheduler>] List of the scheduler delegates
    attr_reader :schedulers

    def initialize(schedulers)
      @schedulers = schedulers
    end

    # Delegates to {Scheduler#running?}.
    def running?
      schedulers.all?(&:running?)
    end

    # Delegates to {Scheduler#shutdown?}.
    def shutdown?
      schedulers.all?(&:shutdown?)
    end

    # Delegates to {Scheduler#shutdown}.
    def shutdown(timeout: -1)
      GoodJob._shutdown_all(schedulers, timeout: timeout)
    end

    # Delegates to {Scheduler#restart}.
    def restart(timeout: -1)
      GoodJob._shutdown_all(schedulers, :restart, timeout: timeout)
    end

    # Delegates to {Scheduler#create_thread}.
    def create_thread(state = nil)
      results = []

      if state
        schedulers.any? do |scheduler|
          scheduler.create_thread(state).tap { |result| results << result }
        end
      else
        schedulers.each do |scheduler|
          results << scheduler.create_thread(state)
        end
      end

      if results.any?
        true
      elsif results.any?(false)
        false
      else # rubocop:disable Style/EmptyElse
        nil
      end
    end
  end
end
