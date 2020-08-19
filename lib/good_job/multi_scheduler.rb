module GoodJob
  class MultiScheduler
    attr_reader :schedulers

    def initialize(schedulers)
      @schedulers = schedulers
    end

    def shutdown(wait: true)
      schedulers.each { |s| s.shutdown(wait: wait) }
    end

    def shutdown?
      schedulers.all?(&:shutdown?)
    end

    def restart(wait: true)
      schedulers.each { |s| s.restart(wait: wait) }
    end

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
