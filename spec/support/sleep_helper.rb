# frozen_string_literal: true

module SleepHelper
  TooSlowError = Class.new(StandardError)

  def wait_until(max: 5.seconds, increments_of: 0.1.seconds, &block)
    start_time = Time.current

    loop do
      failed = false

      begin
        GoodJob::BaseRecord.uncached(&block)
      rescue RSpec::Expectations::ExpectationNotMetError
        failed = true
        raise if Time.current > start_time + max
      end
      break unless failed

      sleep increments_of
    end
  end

  def sleep_until(max: 5, increments_of: 0.1, &block)
    so_many = (max.to_f / increments_of).ceil.to_i

    finished = catch(:finished) do
      so_many.times do
        throw(:finished, true) if GoodJob::BaseRecord.uncached(&block)

        sleep increments_of
      end
      false
    end

    raise TooSlowError unless finished
  end
end

RSpec.configure { |c| c.include SleepHelper }
