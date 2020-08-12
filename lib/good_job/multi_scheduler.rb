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

    def create_thread
      schedulers.all?(&:create_thread)
    end
  end
end
