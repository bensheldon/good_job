# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::ThrottledBlock do
  let(:clock) { [1_000.0] }
  let(:calls) { [] }

  before do
    allow_any_instance_of(described_class).to receive(:monotonic_now) { clock.first }
  end

  def advance(seconds)
    clock[0] += seconds
  end

  it 'does not call the block until the interval has elapsed since it was created' do
    throttled_block = described_class.new(5) { |value| calls << value }

    advance(4.99)
    expect(throttled_block.call(:first)).to be_nil
    advance(0.01)
    throttled_block.call(:second)

    expect(calls).to eq [:second]
  end

  it 'waits for another interval after calling the block' do
    throttled_block = described_class.new(5) { |value| calls << value }

    advance(5)
    throttled_block.call(:first)
    advance(4)
    throttled_block.call(:second)
    advance(1)
    throttled_block.call(:third)

    expect(calls).to eq %i[first third]
  end

  it "returns the block's return value" do
    throttled_block = described_class.new(5) { :result }

    advance(5)
    expect(throttled_block.call).to eq :result
  end

  it 'lengthens each interval by up to the jitter' do
    allow_any_instance_of(described_class).to receive(:rand) { |*args| args.last.max }
    throttled_block = described_class.new(10, jitter: 0.15) { |value| calls << value }

    advance(11.49)
    throttled_block.call(:first)
    advance(0.02)
    throttled_block.call(:second)

    expect(calls).to eq [:second]
  end

  it 'never shortens an interval' do
    allow_any_instance_of(described_class).to receive(:rand) { |*args| args.last.min }
    throttled_block = described_class.new(10, jitter: 0.15) { |value| calls << value }

    advance(9.99)
    throttled_block.call(:first)

    expect(calls).to be_empty
  end
end
