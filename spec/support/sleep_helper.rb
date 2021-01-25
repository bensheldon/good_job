module SleepHelper
  TooSlowError = Class.new(StandardError)

  def wait_until(max: 5, increments_of: 0.1)
    start_time = Time.current

    loop do
      failed = false

      begin
        yield
      rescue RSpec::Expectations::ExpectationNotMetError
        failed = true
        raise if Time.current > start_time + max
      end
      break unless failed

      sleep increments_of
    end
  end

  def sleep_until(max: 5, increments_of: 0.1)
    so_many = (max.to_f / increments_of).ceil.to_i

    finished = catch(:finished) do
      so_many.times do
        throw(:finished, true) if yield

        sleep increments_of
      end
      false
    end

    raise TooSlowError unless finished
  end
end

RSpec.configure { |c| c.include SleepHelper }
