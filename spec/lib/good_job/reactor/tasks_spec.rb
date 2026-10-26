# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::Reactor::Resource do # rubocop:disable RSpec/SpecFilePathFormat
  include ReactorSpecHelpers

  it 'passes the resource to resource.post' do
    resource = fake_resource
    reactor.start

    expect(resource.post { |r| r }.value!).to be resource
    expect(resource.post { |r| r.value.id }.value!).to eq 1
  end

  it 'records the generation results ran on' do
    resource = fake_resource
    reactor.start
    result = resource.post { :ok }

    expect(result.value!.then { result.generation.value.id }).to eq 1
  end

  it 'returns errors in work in the result' do
    resource = fake_resource
    reactor.start
    result = resource.post { raise ArgumentError, "bad job" }

    expect(result).to be_failed
    expect(result.error.message).to eq "bad job"
  end

  it 'wraps posts, watchers and timers with around_task' do
    resource = fake_resource
    wrapped = Concurrent::Collection::TimeoutQueue.new
    resource.around_task do |task, generation|
      wrapped << generation.value.id
      task.call
    end
    resource.every(10) { :tick }
    reactor.start

    resource.post { :post }.value!
    expect(wrapped.pop(timeout: 2)).to eq 1

    watched = Concurrent::Collection::TimeoutQueue.new
    on_loop do
      generation = resource.current_generation
      generation.watch(generation.value.reader) { |g| watched << g.value.reader.read_nonblock(10) }
    end
    connections.first.writer.write("notify")
    expect(watched.pop(timeout: 2)).to eq "notify"
    expect(wrapped.pop(timeout: 2)).to eq 1

    advance(10)
    expect(wrapped.pop(timeout: 2)).to eq 1
  end

  it 'lets around_task fault the generation' do
    resource = fake_resource(on_fault: ->(*_args) { 5 })
    resource.around_task do |task, generation|
      task.call
    rescue IOError => e
      generation.fault(e)
      raise
    end
    reactor.start

    result = resource.post { raise IOError, "connection lost" }
    settle

    expect(result).to be_failed
    expect(log).to include [:remove, 1]
    advance(5)
    expect(resource.post { |r| r.value.id }.value!).to eq 2
  end

  it 'skips a task not run by around_task' do
    resource = fake_resource
    resource.around_task do |task, generation|
      next generation.fault(IOError.new("connection is not active")) unless generation.value.open?

      task.call
    end
    reactor.start
    connections.first.close

    expect(resource.post { :never }).to be_skipped
  end

  it "sends watcher errors to the generation's on_error" do
    resource = fake_resource
    errors = Concurrent::Collection::TimeoutQueue.new
    reactor.start
    on_loop do
      generation = resource.current_generation
      generation.on_error { |error| errors << error }
      generation.watch(generation.value.reader) { raise "dispatch failed" }
    end
    connections.first.writer.write("x")

    expect(errors.pop(timeout: 2).message).to eq "dispatch failed"
  end

  it 'stops generation watchers when removed' do
    resource = fake_resource(retirement_age: 60)
    seen = []
    reactor.start
    on_loop do
      generation = resource.current_generation
      generation.every(10) { |g| seen << g.value.id }
    end
    advance(10)
    advance(50)
    advance(10)

    expect(seen.uniq).to eq [1]
  end

  it 'runs resource.every on whichever generation is current' do
    resource = fake_resource(retirement_age: 60)
    seen = []
    resource.every(25) { |r| seen << r.value.id }
    reactor.start
    3.times { advance(25) }

    expect(seen).to eq [1, 1, 2]
  end
end
