# frozen_string_literal: true

module GoodJob
  class Reactor
    class Resource
      # One instance of a resource, representing one generation of it, attached
      # to the reactor's loop. Its state changes only on the loop thread.
      class Generation
        STATES = %i[promoting current retiring removed].freeze

        attr_reader :resource, :state, :fault_error
        attr_accessor :value

        def initialize(resource, loop)
          @resource = resource
          @loop = loop
          @state = :promoting
          @value = nil
          @fault_error = nil
          @created_at = loop.clock.now
          @claims = Concurrent::AtomicFixnum.new(0)
          @queued = Concurrent::AtomicFixnum.new(0)
          @handles = []
          @error_handlers = []
        end

        def age
          @loop.clock.now - @created_at
        end

        def alive?
          @state != :removed && !fault?
        end

        def fault?
          !@fault_error.nil?
        end

        def current?
          @state == :current
        end

        def claims
          @claims.value
        end

        # @!visibility private
        def queued
          @queued.value
        end

        # Posts work pinned to this generation. It receives the generation, and is
        # skipped if the generation has been removed by the time it runs.
        def post(&block)
          result = Result.new
          @queued.increment
          begin
            @loop.dispatch do
              @queued.decrement
              perform(result) { block.call(self) }
              @resource.check_drain(self)
            end
          rescue NotRunningError
            @queued.decrement
            raise
          end
          result
        end

        # Calls the block whenever `io` is readable, until removed.
        def watch(io, &block)
          track(@loop.watch(io) { perform { block.call(self) } })
        end

        def every(seconds, jitter: 0, &block)
          track(@loop.every(seconds, jitter: jitter) { perform { block.call(self) } })
        end

        # Returns a Claim; with a block, yields it and releases it afterward.
        def claim
          raise ClaimRefusedError, "#{inspect} cannot take new claims" unless accepting_claims?

          @claims.increment
          claim = Claim.new(self)
          return claim unless block_given?

          begin
            yield claim
          ensure
            claim.release
          end
        end

        # Marks the generation broken. It is removed on the loop thread.
        def fault(error)
          return if fault?

          @fault_error = error
          @loop.defer { @resource.handle_fault(self) }
          nil
        end

        # Errors raised by this generation's watchers and timers.
        def on_error(&block)
          @error_handlers << block
          self
        end

        def inspect
          ["#<#{self.class.name}", @resource.name&.inspect, @state, ("fault" if fault?)].compact.join(" ") + ">"
        end

        # @!visibility private
        # Runs the block for this generation inside the resource's around_task
        # hooks. With a result, resolves it; without one, reports errors.
        def perform(result = nil)
          return result&.skip unless alive?

          ran = false
          value = nil
          @resource.around_task_chain(self) do
            ran = true
            value = yield
          end
          if result
            ran ? result.fulfill(value, self) : result.skip
          end
        rescue Exception => e # rubocop:disable Lint/RescueException
          result ? result.reject(e, self) : report_error(e)
        end

        # @!visibility private
        def release_claim
          @claims.decrement
          @loop.defer { @resource.check_drain(self) }
        end

        # @!visibility private
        def state=(state)
          raise ArgumentError, "unknown state #{state.inspect}" unless STATES.include?(state)

          @state = state
        end

        # @!visibility private
        def fault_error=(error)
          @fault_error ||= error
        end

        # @!visibility private
        def removed!
          @handles.each(&:cancel)
          @handles.clear
          @state = :removed
        end

        private

        def accepting_claims?
          alive? && @resource.running? && !(@resource.exclusive? && @state == :retiring)
        end

        def track(handle)
          @handles << handle
          handle
        end

        def report_error(error)
          if @error_handlers.empty?
            @loop.report_error(error)
          else
            @error_handlers.each { |handler| handler.call(error) }
          end
        end
      end
    end
  end
end
