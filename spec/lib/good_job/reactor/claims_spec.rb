# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::Reactor::Claim do # rubocop:disable RSpec/SpecFilePathFormat
  include ReactorSpecHelpers

  it 'keeps a retired generation from being removed' do
    resource = fake_resource(retirement_age: 60)
    reactor.start
    claim = on_loop { resource.claim }
    log.clear
    advance(60)

    expect(log).to eq [[:add, 2], [:promotion, 1, 2]]
    on_loop do
      expect(claim.generation.state).to eq :retiring
      expect(resource.retiring_generations).to eq [claim.generation]
    end

    claim.release
    settle
    expect(log).to eq [[:add, 2], [:promotion, 1, 2], [:remove, 1]]
  end

  it 'keeps locks taken with a claim through rotation until unlocked' do
    resource = fake_resource(retirement_age: 60)
    reactor.start
    claim = resource.post do |r|
      r.value.lock(:job_1)
      r.claim
    end.value!
    advance(60)

    expect(connections.first.locks).to eq [:job_1]
    unlocked = claim.post { |generation| generation.value.unlock(:job_1) }
    claim.release
    settle

    expect(unlocked).to be_ok
    expect(connections.first).not_to be_open
  end

  it 'runs claim.post on the claim generation, not the current one' do
    resource = fake_resource(retirement_age: 60)
    reactor.start
    claim = on_loop { resource.claim }
    advance(60)

    expect(claim.post { |generation| generation.value.id }.value!).to eq 1
    expect(resource.post { |r| r.value.id }.value!).to eq 2
  ensure
    claim&.release
  end

  it 'still runs work posted before release' do
    resource = fake_resource(retirement_age: 60)
    reactor.start
    claim = on_loop { resource.claim }
    advance(60)

    result = nil
    on_loop do
      result = claim.post { |generation| generation.value.id }
      claim.release
    end
    settle

    expect(result.value!).to eq 1
  end

  it 'raises when posting through a released claim' do
    resource = fake_resource
    reactor.start
    claim = on_loop { resource.claim }
    claim.release
    claim.release

    expect(claim).to be_released
    expect { claim.post { :never } }.to raise_error(GoodJob::Reactor::ClaimReleasedError)
  end

  it 'releases the claim in block form' do
    resource = fake_resource
    reactor.start
    generation = on_loop do
      resource.claim { |claim| expect(claim.generation.claims).to eq 1 }
      resource.current_generation
    end

    expect(generation.claims).to eq 0
  end

  it 'skips pinned work on a removed generation' do
    resource = fake_resource(retirement_age: 60)
    reactor.start
    generation = on_loop { resource.current_generation }
    advance(60)

    result = generation.post { :never }
    expect(result).to be_skipped
    expect { result.value! }.to raise_error(GoodJob::Reactor::SkippedError)
  end

  it 'makes an exclusive resource wait for claims before adding' do
    resource = fake_resource(retirement_age: 60, exclusive: true)
    reactor.start
    claim = on_loop { resource.claim }
    log.clear
    advance(60)

    expect(log).to be_empty
    pending = resource.post { |r| r.value.id }
    settle
    expect(pending).not_to be_resolved
    expect { on_loop { claim.generation.claim } }.to raise_error(GoodJob::Reactor::ClaimRefusedError)

    claim.release
    settle
    expect(log).to eq [[:remove, 1], [:add, 2], [:promotion, 1, 2]]
    expect(pending.value!).to eq 2
  end

  it 'removes claimed generations when stopping with a zero timeout' do
    resource = fake_resource(retirement_age: 60)
    reactor.start
    on_loop { resource.claim }
    advance(60)
    reactor.stop(timeout: 0)

    expect(connections.none?(&:open?)).to be true
  end
end
