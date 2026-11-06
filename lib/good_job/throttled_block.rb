# frozen_string_literal: true

module GoodJob
  # @!visibility private
  # Calls a block at most once per interval, measured with the monotonic clock
  # since it was created or the block was last called. Each interval can be
  # randomly lengthened, so that instances created at the same time (e.g. after
  # a deploy) don't keep calling their blocks in lockstep.
  #
  # An instance is not thread-safe.
  class ThrottledBlock
    # @param interval [Numeric] minimum number of seconds between calls of the block
    # @param jitter [Float] proportion by which each interval is randomly lengthened, e.g. +0.15+ for up to 15%
    # @yield the block to throttle, with the arguments passed to {#call}
    def initialize(interval, jitter: 0.0, &block)
      @interval = interval
      @jitter = jitter
      @block = block
      @last_called_at = monotonic_now
      @wait = next_wait
    end

    # Calls the block if at least the interval has elapsed since initialization
    # or the block was last called.
    # @return [Object, nil] the block's return value, or +nil+ if the call was throttled
    def call(...)
      return if monotonic_now - @last_called_at < @wait

      @last_called_at = monotonic_now
      @wait = next_wait
      @block.call(...)
    end

    private

    def next_wait
      @interval * (1 + rand(0..@jitter))
    end

    def monotonic_now
      ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    end
  end
end
