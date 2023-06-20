# frozen_string_literal: true
module GoodJob # :nodoc:
  class Metrics
    def initialize
      @failed_count = Concurrent::AtomicFixnum.new
      @succeeded_count = Concurrent::AtomicFixnum.new
    end

    def failed_count
      @failed_count.value
    end

    def succeeded_count
      @succeeded_count.value
    end

    def increment_failed
      @failed_count.increment
    end

    def increment_succeeded
      @succeeded_count.increment
    end

    def total_count
      failed_count + succeeded_count
    end

    def reset
      @failed_count.value = 0
      @succeeded_count.value = 0
    end
  end
end
