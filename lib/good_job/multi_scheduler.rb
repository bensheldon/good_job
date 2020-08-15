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
      if state
        schedulers.any? { |scheduler| scheduler.create_thread(state) }
      else
        results = schedulers.map { |scheduler| scheduler.create_thread(state) }
        return nil if results.all(&:nil?)

        results.any?
      end
    end
  end
end
