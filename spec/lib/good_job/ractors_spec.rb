# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::Ractors do
  describe '.local' do
    it 'initializes the value once per key' do
      key = :"good_job_ractors_spec_#{SecureRandom.hex}"
      value = described_class.local(key) { Object.new }

      expect(described_class.local(key) { Object.new }).to equal value
    end
  end

  describe '.on_main' do
    it 'runs the block with the given object as self' do
      object = Struct.new(:value).new(42)

      expect(described_class.on_main(object) { value }).to eq 42
    end
  end

  describe '.try_shareable_proc' do
    it 'returns non-procs unchanged' do
      expect(described_class.try_shareable_proc(nil)).to be_nil
      expect(described_class.try_shareable_proc(:on_unhandled_error)).to eq :on_unhandled_error
    end
  end

  describe '.main?' do
    it 'is true on the main Ractor' do
      expect(described_class.main?).to be true
    end
  end
end
