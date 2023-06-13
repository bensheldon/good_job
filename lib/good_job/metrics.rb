# frozen_string_literal: true
module GoodJob # :nodoc:
  class Metrics
    attr_reader :failed_count, :succeeded_count

    def initialize
      @failed_count = 0
      @succeeded_count = 0
    end

    def increment_failed
      @failed_count += 1
    end

    def increment_succeeded
      @succeeded_count += 1
    end
  end
end
