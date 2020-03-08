module SleepHelper
  def sleep_until(max: 5, increments_of: 0.1)
    so_many = (max.to_f / increments_of).ceil.to_i

    so_many.times do
      break if yield

      sleep increments_of
    end
  end
end

RSpec.configure { |c| c.include SleepHelper }
