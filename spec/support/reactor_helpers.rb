# frozen_string_literal: true

# Helpers for the GoodJob::Reactor specs (ported from PebbleBed's test_helper).
# Include with `include ReactorSpecHelpers` in a reactor spec.
module ReactorSpecHelpers
  # A clock that only moves when advanced, waking any loop reading it.
  class ManualClock
    def initialize
      @now = 0.0
      @listeners = []
    end

    attr_reader :now

    def on_advance(&block)
      @listeners << block
    end

    def advance(seconds)
      @now += seconds
      @listeners.each(&:call)
    end
  end

  # A stand-in resource value: a numbered connection that can hold locks only
  # while open, and exposes a pipe so tests can make it readable.
  class FakeConnection
    attr_reader :id, :locks, :reader, :writer

    def initialize(id)
      @id = id
      @open = true
      @locks = []
      @reader, @writer = IO.pipe
    end

    def open?
      @open
    end

    def close
      @open = false
      @locks.clear
      @reader.close
      @writer.close
    end

    def lock(key)
      raise IOError, "connection #{@id} is closed" unless open?

      @locks << key
    end

    def unlock(key)
      raise IOError, "connection #{@id} is closed" unless open?

      @locks.delete(key)
    end
  end

  def self.included(base)
    base.class_eval do
      let(:clock) { ManualClock.new }
      let(:reactor) { GoodJob::Reactor.new(name: "test", clock: clock) }
      let(:log) { [] }
      let(:connections) { [] }

      after do
        reactor.stop(timeout: 0) while reactor.started?
      end
    end
  end

  # A resource whose generations are FakeConnections, logging each lifecycle
  # event as [event, connection id(s)].
  def fake_resource(name: :connection, **options)
    resource = reactor.create_resource(name: name, **options)
    resource.around_add do |add, generation|
      connection = FakeConnection.new(connections.size + 1)
      connections << connection
      generation.value = connection
      log << [:add, connection.id]
      add.call
    end
    resource.around_promotion do |promotion, old_gen, new_gen|
      log << [:promotion, old_gen&.value&.id, new_gen&.value&.id]
      promotion.call
    end
    resource.around_remove do |remove, generation|
      remove.call
    ensure
      log << [:remove, generation.value&.id]
      generation.value&.close
    end
    resource
  end

  # Runs due timers and everything queued on the loop, repeatedly, so work that
  # schedules more work also completes.
  def settle(times = 5)
    times.times do
      reactor.loop.post { reactor.loop.send(:run_due_timers) }.value!
    end
  end

  def advance(seconds)
    clock.advance(seconds)
    settle
  end

  def on_loop(&block)
    reactor.loop.post(&block).value!
  end
end
