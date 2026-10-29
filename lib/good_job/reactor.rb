# frozen_string_literal: true

require "concurrent/atomic/atomic_boolean"
require "concurrent/atomic/atomic_fixnum"
require "concurrent/atomic/event"
require "concurrent/promises"
require_relative "reactor/errors"
require_relative "reactor/clock"
require_relative "reactor/result"
require_relative "reactor/middleware"
require_relative "reactor/loop"
require_relative "reactor/claim"
require_relative "reactor/generation"
require_relative "reactor/resource"

module GoodJob
  # Vendored from https://github.com/bensheldon/pebble_bed
  #
  # A set of resources sharing one loop and one thread, started and stopped
  # together.
  class Reactor
    # Seconds to wait for generations to be removed after a stop times out, beyond the stop's timeout
    FORCED_REMOVAL_TIMEOUT = 10

    attr_reader :name, :loop

    def initialize(name: "pebble_bed", clock: Clock.new)
      @name = name
      @loop = Loop.new(name: name, clock: clock)
      @resources = []
      @failure_handlers = []
      @transition = Mutex.new
      @starts = 0
      @drained = Concurrent::Event.new
      @stop_when_drained = false
    end

    # `name` is an optional label for logs, errors, and inspection; it need not
    # be unique.
    #
    # `retirement_age` is the number of seconds (anything responding to `to_f`)
    # after which the current generation starts retiring and a new one is
    # added; nil never rotates.
    #
    # `on_fault` is called on the reactor thread after each fault, with the
    # faulted generation and the number of faults in a row (reset by a
    # successful promotion). It returns the number of seconds to wait before
    # adding a new generation, or nil to add none; it is also where to stop the
    # reactor or exit the process. If it raises, the reactor fails.
    def create_resource(name: nil, retirement_age: nil, on_fault: Resource::DEFAULT_ON_FAULT, exclusive: false)
      resource = Resource.new(self, @loop, name, retirement_age: retirement_age, on_fault: on_fault, exclusive: exclusive)
      @resources << resource
      @loop.post { resource.start! }.value! if started?
      resource
    end

    def resources
      @resources.dup
    end

    # Called after a fatal failure has stopped everything.
    def on_failure(&block)
      @failure_handlers << block
      self
    end

    def started?
      @loop.running?
    end

    def stopped?
      !started?
    end

    # Counts a start; the first start launches the loop and adds a generation of
    # every resource. With a block, yields and then stops, waiting as `stop` does with
    # its default timeout. With `wait: false`, returns without waiting for the
    # first generations to be added.
    def start(wait: true)
      @transition.synchronize do
        @starts += 1
        if @starts == 1
          @loop.start
          result = @loop.post { @resources.each(&:start!) }
          result.value! if wait
        end
      end
      return self unless block_given?

      begin
        yield self
      ensure
        stop
      end
    end

    # Counts a stop. The stop that balances the last start stops the reactor:
    # every resource stops rotating and retires its current generation, and
    # generations are removed as their claims and queued work finish.
    #
    # `timeout` is the number of seconds to wait for that:
    # * `-1` waits until every generation has drained.
    # * `0` removes every generation immediately, regardless of claims.
    # * A positive number waits that long, then removes what remains.
    # * `nil` begins stopping and returns without waiting; the loop stops once
    #   every generation has drained.
    #
    # Returns whether every generation drained without being forced (true when
    # starts remain or the reactor was already stopped), or nil when not
    # waiting. Called on the reactor thread, it never waits: it returns nil and
    # stops from another thread.
    def stop(timeout: -1)
      # On the reactor thread, waiting would block the work being waited for,
      # so stopping continues on another thread.
      if @loop.on_thread?
        Thread.new { stop(timeout: timeout) }
        return nil
      end

      @transition.synchronize do
        return finish_stop(timeout) if @starts.zero?

        @starts -= 1
        @starts.zero? ? stop_now(timeout) : true
      end
    end

    # Waits for a stop that has already begun, as `stop` does with `timeout`,
    # without counting a stop. Returns false when starts remain.
    def wait_for_stop(timeout: -1)
      @transition.synchronize do
        @starts.zero? ? finish_stop(timeout) : false
      end
    end

    def inspect
      "#<#{self.class.name} #{@name.inspect}>"
    end

    # @!visibility private
    # Called on the loop thread: removes every generation of every
    # resource regardless of starts and claims, stops the loop, and reports the
    # error.
    def fail!(error)
      @resources.each(&:stop!)
      Thread.new do
        @transition.synchronize do
          @starts = 0
          @loop.stop(force: true)
        end
        @failure_handlers.each { |handler| handler.call(error) }
      end
    end

    # @!visibility private
    # Called on the loop thread whenever a generation is removed while
    # stopping.
    def check_drained
      return unless @resources.all?(&:drained?)

      @drained.set
      return unless @stop_when_drained

      @stop_when_drained = false
      Thread.new { @loop.stop(force: true) }
    end

    private

    def stop_now(timeout)
      return true unless started?

      @drained.reset
      @stop_when_drained = timeout.nil?
      # Retiring runs remove hooks on the loop thread, which can block; wait for them only as long as the timeout allows.
      @retiring = @loop.post { @resources.each(&:begin_stop!) }
      finish_stop(timeout)
    end

    # Waits for a stop that has already begun, as `stop` does with `timeout`.
    # Lets a stop that began without waiting be waited on later.
    def finish_stop(timeout)
      unless started?
        # A stop that timed out leaves the loop stopped while its thread finishes queued removal.
        return !@loop.alive? if timeout.nil?

        return @loop.join(timeout.negative? ? nil : timeout)
      end
      return nil if timeout.nil?

      deadline = monotonic_now + timeout unless timeout.negative?
      @retiring&.wait(remaining(deadline))
      drained = @drained.wait(remaining(deadline))
      # Removal may queue behind blocked remove hooks, so it is waited on for at most FORCED_REMOVAL_TIMEOUT;
      # the loop runs it before its thread exits.
      @loop.post { @resources.each(&:stop!) } unless drained
      @loop.stop(timeout: drained ? remaining(deadline) : FORCED_REMOVAL_TIMEOUT, force: true)
      drained
    end

    def remaining(deadline)
      deadline && [deadline - monotonic_now, 0].max
    end

    def monotonic_now
      ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    end
  end
end
