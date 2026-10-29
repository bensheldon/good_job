# frozen_string_literal: true

module GoodJob
  class Reactor
    # Runs around_* hooks as middleware: the first registered is outermost, and
    # each receives the next layer as a callable followed by `args`.
    module Middleware
      # Returns whether the innermost layer (`core`) was reached.
      def self.call(hooks, args, &core)
        reached = false
        innermost = lambda do
          reached = true
          core&.call
        end
        hooks.reverse.inject(innermost) { |inner, hook| -> { hook.call(inner, *args) } }.call
        reached
      end
    end
  end
end
