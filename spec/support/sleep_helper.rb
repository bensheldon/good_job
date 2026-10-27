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

  # Waits until the block's expectations pass, failing only if work stops progressing.
  # Unlike `wait_until`, there is no fixed total deadline: the timer resets whenever
  # `progress` returns a new value, so a slow (e.g. heavily loaded) database can't fail the
  # spec, but a hang still does. Uses a monotonic clock so it is unaffected by Timecop.
  #
  # @param progress [Proc] returns a value that changes as work advances (e.g. a finished count)
  # @param stalled_after [Numeric] seconds without a change in `progress` before failing
  def wait_while_progressing(progress:, stalled_after: 60, increments_of: 0.5, &block)
    last_progress = nil
    last_progress_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    loop do
      begin
        GoodJob::BaseRecord.uncached(&block)
        break
      rescue RSpec::Expectations::ExpectationNotMetError
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        current_progress = GoodJob::BaseRecord.uncached(&progress)
        if current_progress != last_progress
          last_progress = current_progress
          last_progress_at = now
        elsif now - last_progress_at > stalled_after
          Thread.list.each { |thread| warn "#{thread.name || thread.inspect}:\n  #{thread.backtrace&.first(15)&.join("\n  ")}" }
          raise
        end
      end

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
