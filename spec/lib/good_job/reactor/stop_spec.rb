# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::Reactor do # rubocop:disable RSpec/SpecFilePathFormat
  include ReactorSpecHelpers

  def claim_lock(resource, key)
    resource.post do |r|
      r.value.lock(key)
      r.claim
    end.value!
  end

  def wait_until_stopping(resource)
    sleep 0.001 until on_loop { !resource.running? }
  end

  describe '#stop' do
    it 'waits for claims to be released' do
      resource = fake_resource
      reactor.start
      claim = claim_lock(resource, :job_1)
      stopper = Thread.new { reactor.stop(timeout: -1) }
      wait_until_stopping(resource)

      expect(connections.first).to be_open
      unlocked = claim.post { |generation| generation.value.unlock(:job_1) }
      claim.release

      expect(stopper.value).to be_truthy
      expect(unlocked).to be_ok
      expect(connections.first).not_to be_open
      expect(reactor).not_to be_started
    end

    it 'forces remove after the timeout' do
      resource = fake_resource
      reactor.start
      claim_lock(resource, :job_1)

      expect(reactor.stop(timeout: 0.05)).to be_falsey
      expect(connections.first).not_to be_open
      expect(reactor).not_to be_started
    end

    it 'removes immediately with a zero timeout' do
      resource = fake_resource
      reactor.start
      claim_lock(resource, :job_1)

      expect(reactor.stop(timeout: 0)).to be_falsey
      expect(connections.first).not_to be_open
    end

    it 'drains immediately without claims' do
      fake_resource
      reactor.start

      expect(reactor.stop(timeout: -1)).to be_truthy
      expect(reactor).to be_stopped
    end

    it 'returns with a nil timeout and stops once drained' do
      resource = fake_resource
      reactor.start
      claim = claim_lock(resource, :job_1)

      expect(reactor.stop(timeout: nil)).to be_nil
      expect(reactor).to be_started

      claim.release
      sleep 0.001 while reactor.started?
      expect(connections.first).not_to be_open
    end

    it 'allows no new claims or unpinned work while stopping' do
      resource = fake_resource
      reactor.start
      claim = claim_lock(resource, :job_1)
      stopper = Thread.new { reactor.stop(timeout: -1) }
      wait_until_stopping(resource)

      expect(resource.post { :never }).to be_skipped
      expect { on_loop { claim.generation.claim } }.to raise_error(GoodJob::Reactor::ClaimRefusedError)

      claim.release
      stopper.join
    end

    it 'waits for claims when a start block stops' do
      resource = fake_resource
      claim = nil
      releaser = nil
      reactor.start do
        claim = claim_lock(resource, :job_1)
        releaser = Thread.new do
          wait_until_stopping(resource)
          claim.release
        end
      end
      releaser.join

      expect(claim).to be_released
      expect(reactor).not_to be_started
    end

    it 'skips work waiting after a fault when stopping' do
      resource = fake_resource(on_fault: ->(*) { 5 })
      reactor.start
      on_loop { resource.current_generation.fault(IOError.new("connection lost")) }
      settle
      waiting = resource.post { :never }
      log.clear

      expect(reactor.stop(timeout: -1)).to be_truthy
      expect(waiting).to be_skipped
      expect(log).to eq [[:promotion, 1, nil]]
      expect(connections.size).to eq 1
    end

    it 'adds no generation after stop during an exclusive rotation' do
      resource = fake_resource(retirement_age: 60, exclusive: true)
      reactor.start
      claim = on_loop { resource.claim }
      advance(60)
      waiting = resource.post { :never }
      log.clear

      stopper = Thread.new { reactor.stop(timeout: -1) }
      wait_until_stopping(resource)
      expect(waiting).to be_skipped
      claim.release

      expect(stopper.value).to be_truthy
      expect(log).to eq [[:promotion, 1, nil], [:remove, 1]]
      expect(connections.size).to eq 1
    end

    it 'promotes nothing with the faulted generation when stopping in a fault gap' do
      resource = fake_resource(on_fault: ->(*) { 5 })
      promotions = []
      resource.around_promotion do |promotion, old_gen, new_gen|
        promotions << [old_gen, new_gen]
        promotion.call
      end
      reactor.start
      on_loop { resource.current_generation.fault(IOError.new("connection lost")) }
      settle
      reactor.stop

      old_gen, new_gen = promotions.last
      expect(old_gen).to be_fault
      expect(old_gen).not_to be_alive
      expect(new_gen).to be_nil
    end
  end
end
