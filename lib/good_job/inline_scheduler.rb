module GoodJob
  class InlineScheduler
    def enqueue(good_job)
      JobWrapper.new(good_job).perform
    end

    def shutdown(wait: true)
    end
  end
end
