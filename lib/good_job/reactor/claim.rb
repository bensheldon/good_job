# frozen_string_literal: true

module GoodJob
  class Reactor
    # Keeps a generation from being removed until released, for state left
    # on it that must outlive a task.
    class Claim
      attr_reader :generation

      def initialize(generation)
        @generation = generation
        @released = Concurrent::AtomicBoolean.new(false)
      end

      # Posts work pinned to the claim's generation.
      def post(&block)
        raise ClaimReleasedError, "claim has been released" if released?

        @generation.post(&block)
      end

      def release
        @generation.release_claim if @released.make_true
        nil
      end

      def released?
        @released.true?
      end
    end
  end
end
