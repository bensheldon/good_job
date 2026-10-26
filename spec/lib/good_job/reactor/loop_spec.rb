# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::Reactor::Loop do
  let(:clock) { ReactorSpecHelpers::ManualClock.new }
  let!(:reactor_loop) { described_class.new(name: "loop_test", clock: clock).start }

  after do
    reactor_loop.stop(force: true)
  end

  it 'runs posts on the loop thread and returns a result' do
    result = reactor_loop.post { Thread.current.name }

    expect(result.value!).to eq "loop_test"
    expect(result).to be_ok
  end

  it 'captures errors in the result' do
    result = reactor_loop.post { raise ArgumentError, "boom" }

    expect(result).to be_failed
    expect(result.error).to be_an_instance_of ArgumentError
    expect { result.value! }.to raise_error(ArgumentError)
  end

  it 'runs posts from the loop thread immediately' do
    inner_resolved = reactor_loop.post { reactor_loop.post { :inner }.resolved? }.value!

    expect(inner_resolved).to be true
  end

  it 'calls back a watcher when the io is readable' do
    reader, writer = IO.pipe
    seen = Concurrent::Collection::TimeoutQueue.new
    reactor_loop.watch(reader) { seen << reader.read_nonblock(10) }
    writer.write("hi")

    expect(seen.pop(timeout: 2)).to eq "hi"
  ensure
    reader&.close
    writer&.close
  end

  it 'fires timers following the clock' do
    fired = Concurrent::Collection::TimeoutQueue.new
    reactor_loop.after(5) { fired << :after }
    reactor_loop.every(2) { fired << :every }

    clock.advance(2)
    expect(fired.pop(timeout: 2)).to eq :every
    clock.advance(3)
    expect([fired.pop(timeout: 2), fired.pop(timeout: 2)].sort).to eq [:after, :every].sort
  end

  it 'does not fire canceled timers' do
    fired = []
    timer = reactor_loop.after(1) { fired << :fired }
    timer.cancel
    clock.advance(2)
    reactor_loop.post { reactor_loop.send(:run_due_timers) }.value!

    expect(fired).to be_empty
  end

  it 'sends watcher and timer errors to on_error' do
    errors = Concurrent::Collection::TimeoutQueue.new
    reactor_loop.on_error { |error| errors << error }
    reactor_loop.after(1) { raise "timer failed" }
    clock.advance(1)

    expect(errors.pop(timeout: 2).message).to eq "timer failed"
  end

  it 'counts starts' do
    reactor_loop.start
    expect(reactor_loop.stop).to be_truthy
    expect(reactor_loop).to be_running

    reactor_loop.stop
    expect(reactor_loop).not_to be_running
  end

  it 'raises when posting while stopped' do
    reactor_loop.stop

    expect { reactor_loop.post { :never } }.to raise_error(GoodJob::Reactor::NotRunningError)
  end
end
