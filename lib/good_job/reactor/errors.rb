# frozen_string_literal: true

module GoodJob
  class Reactor
    class Error < StandardError; end

    # Raised when work is submitted to a reactor or loop that is not running.
    class NotRunningError < Error; end

    # Raised when posting through a claim that has been released.
    class ClaimReleasedError < Error; end

    # Raised when a claim is requested on a generation that cannot take one.
    class ClaimRefusedError < Error; end

    # Raised when the resource has no current generation to act on.
    class NoCurrentGenerationError < Error; end

    # Raised when an around_* hook returns without calling the next layer.
    class IncompleteHookError < Error; end

    # Raised by Result#value! when the work was skipped.
    class SkippedError < Error; end
  end
end
