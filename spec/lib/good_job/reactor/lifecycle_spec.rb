# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::Reactor do # rubocop:disable RSpec/SpecFilePathFormat
  include ReactorSpecHelpers

  it 'adds and promotes a generation on start' do
    resource = fake_resource
    reactor.start

    expect(log).to eq [[:add, 1], [:promotion, nil, 1]]
    on_loop do
      expect(resource.current_generation.state).to eq :current
      expect(resource.value.id).to eq 1
    end
  end

  it 'promotes nothing and removes the current generation on stop' do
    fake_resource
    reactor.start
    log.clear
    reactor.stop

    expect(log).to eq [[:promotion, 1, nil], [:remove, 1]]
    expect(reactor).not_to be_started
  end

  it 'rotates by adding, then promoting, then removing' do
    resource = fake_resource(retirement_age: 60)
    reactor.start
    log.clear
    advance(60)

    expect(log).to eq [[:add, 2], [:promotion, 1, 2], [:remove, 1]]
    on_loop { expect(resource.value.id).to eq 2 }
  end

  it 'continues rotating at each retirement age' do
    fake_resource(retirement_age: 60)
    reactor.start
    advance(60)
    advance(60)

    expect(connections.map(&:id)).to eq [1, 2, 3]
    expect(connections.map { |connection| !connection.open? }).to eq [true, true, false]
  end

  it 'removes before adding in an exclusive rotation' do
    fake_resource(retirement_age: 60, exclusive: true)
    reactor.start
    log.clear
    advance(60)

    expect(log).to eq [[:remove, 1], [:add, 2], [:promotion, 1, 2]]
  end

  it 'never has two open values for an exclusive resource' do
    fake_resource(retirement_age: 60, exclusive: true)
    max_open = 0
    reactor.start
    3.times do
      advance(60)
      max_open = [max_open, connections.count(&:open?)].max
    end

    expect(max_open).to eq 1
  end

  it 'removes on fault, then adds after the delay from on_fault' do
    resource = fake_resource(on_fault: ->(*_args) { 5 })
    reactor.start
    log.clear
    on_loop { resource.current_generation.fault(IOError.new("connection lost")) }
    settle

    expect(log).to eq [[:remove, 1]]
    on_loop { expect(resource.current_generation).to be_nil }

    advance(5)
    expect(log).to eq [[:remove, 1], [:add, 2], [:promotion, 1, 2]]
  end

  it 'passes the faulted generation to promotion as not alive' do
    resource = fake_resource(on_fault: ->(*_args) { 5 })
    old_gens = []
    resource.around_promotion do |promotion, old_gen, _new_gen|
      old_gens << old_gen
      promotion.call
    end
    reactor.start
    on_loop { resource.current_generation.fault(IOError.new("connection lost")) }
    settle # fault defers handle_fault; let it schedule before the clock moves
    advance(5)

    faulted = old_gens.last
    expect(faulted).to be_fault
    expect(faulted).not_to be_alive
    expect(faulted.fault_error.message).to eq "connection lost"
  end

  it 'treats a failed add as a fault and retries after the delay from on_fault' do
    resource = fake_resource(on_fault: ->(*_args) { 5 })
    attempts = 0
    resource.around_add do |add, _generation|
      attempts += 1
      raise IOError, "database is down" if attempts < 3

      add.call
    end
    reactor.start

    expect(log).to eq [[:add, 1], [:remove, 1]]
    advance(5)
    expect(attempts).to eq 2
    advance(5)
    expect(attempts).to eq 3
    on_loop { expect(resource.value.id).to eq 3 }
  end

  it 'makes unpinned work wait for a current generation' do
    resource = fake_resource(on_fault: ->(*_args) { 5 })
    reactor.start
    on_loop { resource.current_generation.fault(IOError.new("connection lost")) }
    settle

    result = resource.post { |r| r.value.id }
    settle
    expect(result).not_to be_resolved

    advance(5)
    expect(result.value!).to eq 2
  end

  it 'shuts the reactor down on a failed promotion' do
    resource = fake_resource(retirement_age: 60)
    failures = Queue.new
    reactor.on_failure { |error| failures << error }
    resource.around_promotion do |promotion, old_gen, new_gen|
      raise "could not move the heartbeat" if old_gen && new_gen

      promotion.call
    end
    reactor.start
    clock.advance(60)

    expect(ReactorSpecHelpers.pop_within(failures, 2).message).to eq "could not move the heartbeat"
    sleep 0.01 while reactor.started?
    expect(connections.none?(&:open?)).to be true
  end

  it 'counts starts' do
    fake_resource
    reactor.start
    reactor.start do
      expect(reactor).to be_started
    end
    expect(reactor).to be_started

    reactor.stop
    expect(reactor).not_to be_started
  end

  it 'starts a stopped reactor again with a new generation' do
    resource = fake_resource
    reactor.start
    reactor.stop
    reactor.start

    on_loop { expect(resource.value.id).to eq 2 }
  end

  it 'treats resource names as optional labels' do
    unnamed = reactor.create_resource
    first = reactor.create_resource(name: :connection)
    second = reactor.create_resource(name: :connection)

    expect(unnamed.name).to be_nil
    expect(unnamed.inspect).to eq "#<GoodJob::Reactor::Resource>"
    expect(first.inspect).to eq "#<GoodJob::Reactor::Resource :connection>"
    expect(reactor.resources).to eq [unnamed, first, second]
  end

  it 'passes on_fault the faulted generation and the faults in a row' do
    calls = []
    resource = fake_resource(on_fault: lambda { |generation, faults|
      calls << [generation.value&.id, generation.fault_error.message, faults]
      5
    })
    attempts = 0
    resource.around_add do |add, _generation|
      attempts += 1
      raise IOError, "database is down" if attempts.between?(2, 3)

      add.call
    end
    reactor.start
    on_loop { resource.current_generation.fault(IOError.new("connection lost")) }
    settle # fault defers handle_fault; let it schedule before the clock moves
    3.times { advance(5) }

    expect(calls).to eq [[1, "connection lost", 1], [2, "database is down", 2], [3, "database is down", 3]]
    on_loop { expect(resource.value.id).to eq 4 }

    on_loop { resource.current_generation.fault(IOError.new("connection lost")) }
    settle
    expect(calls.last.last).to eq 1
  end

  it 'defaults on_fault to adding a new generation right away' do
    resource = fake_resource
    reactor.start
    on_loop { resource.current_generation.fault(IOError.new("connection lost")) }
    settle

    on_loop { expect(resource.value.id).to eq 2 }
  end

  it 'adds no new generation when on_fault returns nil' do
    resource = fake_resource(on_fault: ->(*_args) {})
    reactor.start
    on_loop { resource.current_generation.fault(IOError.new("connection lost")) }
    advance(60)

    expect(connections.size).to eq 1
    on_loop { expect(resource.current_generation).to be_nil }
  end

  it 'lets on_fault stop the reactor' do
    the_reactor = reactor
    resource = fake_resource(on_fault: ->(*_args) { the_reactor.stop })
    reactor.start
    on_loop { resource.current_generation.fault(IOError.new("connection lost")) }
    sleep 0.001 while reactor.started?

    expect(connections.size).to eq 1
    expect(connections.first).not_to be_open
  end

  it 'fails the reactor on an on_fault error' do
    failures = Queue.new
    reactor.on_failure { |error| failures << error }
    resource = fake_resource(on_fault: ->(*_args) { raise "give up" })
    reactor.start
    on_loop { resource.current_generation.fault(IOError.new("connection lost")) }

    expect(ReactorSpecHelpers.pop_within(failures, 2).message).to eq "give up"
  end

  it 'accepts anything with to_f as retirement_age' do
    duration = Struct.new(:seconds) { delegate :to_f, to: :seconds }.new(60)
    resource = fake_resource(retirement_age: duration)
    reactor.start
    advance(60)

    expect(resource.retirement_age).to eq 60.0
    on_loop { expect(resource.value.id).to eq 2 }
  end
end
