module SleepHelper
  TooSlowError = Class.new(StandardError)

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
