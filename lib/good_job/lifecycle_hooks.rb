# frozen_string_literal: true

module GoodJob # :nodoc:
  # Extends the GoodJob module with a registry of cluster-mode lifecycle
  # callbacks. Blocks registered here run at specific points around forking so
  # applications can close and re-establish resources (database connections,
  # sockets, etc.) that cannot be safely shared across a +fork+. Registered
  # blocks are inherited by forked subprocesses.
  module LifecycleHooks
    extend ActiveSupport::Concern

    # The supported lifecycle events, in the order their hooks are registered.
    EVENTS = %i[
      before_supervisor_fork
      before_subprocess_boot
    ].freeze

    included do
      # @!attribute [rw] _lifecycle_hooks
      #   @!scope class
      #   Registered lifecycle hook blocks, keyed by event name.
      #   @return [Hash{Symbol=>Array<Proc>}]
      mattr_accessor :_lifecycle_hooks, default: EVENTS.index_with { [] }
    end

    class_methods do
      # Register a block to run once in the supervisor, before it forks any
      # subprocess (cluster mode only). Use it to release resources the
      # subprocesses must not inherit, such as open database connections.
      # @yield [void]
      # @return [void]
      # @example Close a Redis connection before forking
      #   # config/initializers/good_job.rb
      #   GoodJob.before_supervisor_fork { Redis.current.close }
      def before_supervisor_fork(&block)
        register_lifecycle_hook(:before_supervisor_fork, &block)
      end

      # Register a block to run in each subprocess after it is forked, before
      # its capsule starts (cluster mode only). Use it to re-establish resources
      # that cannot be shared across a fork.
      # @yield [void]
      # @return [void]
      # @example Reconnect to Redis in each subprocess
      #   # config/initializers/good_job.rb
      #   GoodJob.before_subprocess_boot { Redis.current.reconnect }
      def before_subprocess_boot(&block)
        register_lifecycle_hook(:before_subprocess_boot, &block)
      end

      # @!visibility private
      # @param event [Symbol]
      # @return [void]
      def register_lifecycle_hook(event, &block)
        raise ArgumentError, "Unknown GoodJob lifecycle event: #{event.inspect}" unless EVENTS.include?(event)

        _lifecycle_hooks.fetch(event) << block
      end

      # @!visibility private
      # Runs every block registered for +event+ in registration order, isolating
      # and reporting errors so a misbehaving hook cannot wedge the supervisor or
      # a subprocess.
      # @param event [Symbol]
      # @return [void]
      def run_lifecycle_hooks(event)
        _lifecycle_hooks.fetch(event).each do |block|
          block.call
        rescue StandardError => e
          _on_thread_error(e)
        end
      end

      # Removes every registered lifecycle hook, including GoodJob's built-in
      # connection-management defaults. Primarily useful for resetting global
      # state between tests.
      # @return [void]
      def clear_lifecycle_hooks
        self._lifecycle_hooks = EVENTS.index_with { [] }
      end
    end
  end
end
