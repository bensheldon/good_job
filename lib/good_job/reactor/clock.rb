# frozen_string_literal: true

module GoodJob
  class Reactor
    # Monotonic time in seconds. A loop reads time only through its clock, so a
    # clock that also responds to `on_advance` can drive timers in tests.
    class Clock
      def now
        ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      end
    end
  end
end
