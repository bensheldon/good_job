module GoodJob
  # Delegates the interface of a single {Scheduler} to multiple Schedulers.
  class MultiScheduler
    # @return [array<Scheduler>] List of the scheduler delegates
    attr_reader :schedulers

    def initialize(schedulers)
      @schedulers = schedulers
    end

    # Delegates to {Scheduler#shutdown}.
    def shutdown(wait: true)
      schedulers.each { |s| s.shutdown(wait: wait) }
    end

    # Delegates to {Scheduler#shutdown?}.
    def shutdown?
      schedulers.all?(&:shutdown?)
    end

    # Delegates to {Scheduler#restart}.
    def restart(wait: true)
      schedulers.each { |s| s.restart(wait: wait) }
    end

    # Delegates to {Scheduler#create_thread}.
    def create_thread(state = nil)
      results = []
      any_true = schedulers.any? do |scheduler|
        scheduler.create_thread(state).tap { |result| results << result }
      end

      if any_true
        true
      else
        results.any? { |result| result == false } ? false : nil
      end
    end
  end
end
