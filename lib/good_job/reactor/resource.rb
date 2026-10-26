# frozen_string_literal: true

module GoodJob
  class Reactor
    # One kind of long-lived resource and its generations: one current, and any
    # retiring ones that are not yet safe to remove. Lifecycle methods run
    # only on the loop thread.
    class Resource
      # Adds a new generation right after each fault.
      DEFAULT_ON_FAULT = ->(_generation, _faults) { 0 }

      attr_reader :name, :retirement_age, :reactor

      def initialize(reactor, loop, name, retirement_age:, on_fault:, exclusive:)
        @reactor = reactor
        @loop = loop
        @name = name
        @retirement_age = retirement_age&.to_f
        @on_fault = on_fault
        @faults = 0
        @exclusive = exclusive
        @add_hooks = []
        @promotion_hooks = []
        @remove_hooks = []
        @task_hooks = []
        @current = nil
        @retiring = []
        @pending = []
        @timers = []
        @add_timer = nil
        @recurring = []
        @awaiting_removal = nil
        @running = false
        @stopping = false
        @last_promoted = nil
      end

      def exclusive?
        @exclusive
      end

      def around_add(&block)
        @add_hooks << block
        self
      end

      def around_promotion(&block)
        @promotion_hooks << block
        self
      end

      def around_remove(&block)
        @remove_hooks << block
        self
      end

      def around_task(&block)
        @task_hooks << block
        self
      end

      def current_generation
        @current
      end

      def retiring_generations
        @retiring.dup
      end

      # Posts work to the current generation. It receives the resource. Work posted
      # while there is no current generation waits for the next promotion.
      def post(&block)
        result = Result.new
        @loop.dispatch do
          if (current = @current)
            current.perform(result) { block.call(self) }
          elsif @running
            @pending << [block, result]
          else
            result.skip
          end
        end
        result
      end

      # The current generation's value. Meaningful on the loop thread.
      def value
        current!.value
      end

      # A claim on the current generation. Meaningful on the loop thread.
      def claim(&block)
        generation = current!
        return generation.claim unless block

        generation.claim(&block)
      end

      # Runs the block on whichever generation is current, every `seconds`, while
      # the reactor is running. It receives the resource.
      def every(seconds, &block)
        @recurring << [seconds, block]
        @loop.dispatch { start_recurring(seconds, block) } if @loop.running?
        self
      end

      def inspect
        ["#<#{self.class.name}", @name&.inspect].compact.join(" ") + ">"
      end

      # @!visibility private
      def around_task_chain(generation, &block)
        return block.call if @task_hooks.empty?

        Middleware.call(@task_hooks, [generation], &block)
      end

      # @!visibility private
      def start!
        @running = true
        @stopping = false
        @last_promoted = nil
        @recurring.each { |(seconds, block)| start_recurring(seconds, block) }
        add_next(nil)
      end

      # @!visibility private
      # Whether the resource is running: adding, promoting, and taking
      # claims. False once stopping has begun.
      def running?
        @running
      end

      # @!visibility private
      # Whether every generation has been removed and no work is waiting
      # for one.
      def drained?
        @current.nil? && @retiring.empty? && @pending.empty?
      end

      # @!visibility private
      # Begins stopping: stops rotating and adding, refuses new claims and
      # new work, skips work waiting for a generation, retires the current
      # generation with no successor, and removes retiring generations as
      # they drain.
      def begin_stop!
        return unless @running

        @running = false
        @stopping = true
        @timers.each(&:cancel)
        @timers.clear
        cancel_add
        skip_pending
        # The last promoted generation is retired with no successor. In a gap it
        # has already faulted, or is retiring during an exclusive rotation.
        if @last_promoted
          begin
            promote(@last_promoted, nil)
          rescue Exception => e # rubocop:disable Lint/RescueException
            @loop.report_error(e)
          end
        end
        @current = nil
        @retiring.dup.each { |generation| check_drain(generation) }
        @reactor.check_drained
      end

      # @!visibility private
      # Removes every generation, regardless of claims, and skips work
      # waiting for one.
      def stop!
        begin_stop!
        @stopping = false
        cancel_add
        skip_pending
        [@current, *@retiring].compact.each { |generation| remove(generation) }
        @current = nil
        @retiring.clear
      end

      # @!visibility private
      def handle_fault(generation)
        return if generation.state == :removed

        was_current = generation.equal?(@current)
        awaited = generation.equal?(@awaiting_removal)
        @current = nil if was_current
        @retiring.delete(generation)
        @awaiting_removal = nil if awaited
        remove(generation)
        after_fault(generation, generation) if @running && (was_current || awaited)
      end

      # @!visibility private
      # Removes a retiring generation once nothing needs it.
      def check_drain(generation)
        return unless generation.state == :retiring
        return unless generation.claims.zero? && generation.queued.zero?

        @retiring.delete(generation)
        remove(generation)
        return unless generation.equal?(@awaiting_removal)

        @awaiting_removal = nil
        add_next(generation) if @running
      end

      private

      def cancel_add
        @add_timer&.cancel
        @add_timer = nil
        @awaiting_removal = nil
      end

      def skip_pending
        @pending.each { |(_block, result)| result.skip }
        @pending.clear
      end

      def current!
        @current || raise(NoCurrentGenerationError, "#{inspect} has no current generation")
      end

      def start_recurring(seconds, block)
        @timers << @loop.every(seconds) { @current&.perform { block.call(self) } }
      end

      def add_next(old)
        generation = add
        if generation.fault?
          after_fault(old, generation)
        else
          promote(old, generation)
        end
      end

      # Calls on_fault with the faulted generation and the number of faults in a
      # row, and adds a new generation after the delay it returns. A nil delay
      # adds none.
      def after_fault(old, faulted)
        @faults += 1
        delay = @on_fault.call(faulted, @faults)
        return unless delay && @running

        @add_timer = @loop.after(delay) do
          @add_timer = nil
          add_next(old) if @running
        end
      rescue Exception => e # rubocop:disable Lint/RescueException
        @reactor.fail!(e) if @running
      end

      # Returns the added generation, which has faulted if adding failed.
      def add
        generation = Generation.new(self, @loop)
        begin
          reached = Middleware.call(@add_hooks, [generation])
          raise IncompleteHookError, "around_add did not call add" unless reached

          fault_error = generation.fault_error
          raise fault_error if fault_error
        rescue Exception => e # rubocop:disable Lint/RescueException
          generation.fault_error = e
          remove(generation)
        end
        generation
      end

      def promote(previous_generation, next_generation)
        reached = Middleware.call(@promotion_hooks, [previous_generation, next_generation]) do
          if previous_generation && previous_generation.state == :current
            previous_generation.state = :retiring
            @retiring << previous_generation
          end
          @current = next_generation
          next_generation&.state = :current
          @last_promoted = next_generation
        end
        raise IncompleteHookError, "around_promotion did not call promotion" unless reached
      rescue Exception => e # rubocop:disable Lint/RescueException
        remove(next_generation) if next_generation && !next_generation.equal?(@current)
        raise unless @running

        @reactor.fail!(e)
      else
        return unless next_generation

        @faults = 0
        flush_pending
        schedule_rotation(next_generation)
        check_drain(previous_generation) if previous_generation
      end

      def remove(generation)
        return if generation.state == :removed

        begin
          Middleware.call(@remove_hooks, [generation])
        rescue Exception => e # rubocop:disable Lint/RescueException
          @loop.report_error(e)
        ensure
          generation.removed!
        end
        @reactor.check_drained unless @running
      end

      def flush_pending
        current = @current or return
        pending = @pending
        @pending = []
        pending.each { |(block, result)| current.perform(result) { block.call(self) } }
      end

      def schedule_rotation(generation)
        retirement_age = @retirement_age or return

        @timers.reject!(&:canceled?)
        @timers << @loop.after(retirement_age) { rotate(generation) }
      end

      def rotate(generation)
        return unless @running && generation.equal?(@current)

        if exclusive?
          @current = nil
          generation.state = :retiring
          @retiring << generation
          @awaiting_removal = generation
          check_drain(generation)
        else
          add_next(generation)
        end
      end
    end
  end
end
