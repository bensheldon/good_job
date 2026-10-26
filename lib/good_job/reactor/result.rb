# frozen_string_literal: true

module GoodJob
  class Reactor
    # The outcome of posted work, returned immediately. Reading it waits until the
    # work has run, failed, or been skipped.
    class Result
      attr_reader :generation

      def initialize
        @future = Concurrent::Promises.resolvable_future
        @generation = nil
      end

      def resolved?
        @future.resolved?
      end

      # Waits up to `timeout` seconds (forever when nil). Returns whether resolved.
      def wait(timeout = nil)
        timeout ? @future.wait(timeout) : @future.wait
        resolved?
      end

      def ok?
        outcome.first == :ok
      end

      def failed?
        outcome.first == :failed
      end

      def skipped?
        outcome.first == :skipped
      end

      def value
        ok? ? outcome.last : nil
      end

      def error
        failed? ? outcome.last : nil
      end

      # The value; raises the error if failed, or SkippedError if skipped.
      def value!
        failure = error
        raise failure if failure
        raise SkippedError, "work was skipped" if skipped?

        value
      end

      def inspect
        state = resolved? ? outcome.first : :pending
        "#<#{self.class.name} #{state}>"
      end

      # @!visibility private
      def fulfill(value, generation = nil)
        resolve(:ok, value, generation)
      end

      # @!visibility private
      def reject(error, generation = nil)
        resolve(:failed, error, generation)
      end

      # @!visibility private
      def skip
        resolve(:skipped, nil, nil)
      end

      private

      def resolve(state, payload, generation)
        @generation = generation
        @future.fulfill([state, payload], false)
        self
      end

      # The future is only ever fulfilled, so waiting for its value never yields
      # nil.
      def outcome
        _ = @future.value
      end
    end
  end
end
