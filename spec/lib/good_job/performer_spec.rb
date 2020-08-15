require 'rails_helper'

RSpec.describe GoodJob::Performer do
  subject(:performer) { described_class.new(target, :the_method) }

  let(:target) { double('The Target', the_method: nil) } # rubocop:disable RSpec/VerifiedDoubles

  describe '#next' do
    it 'delegates to target#method_name' do
      performer.next
      expect(target).to have_received(:the_method)
    end
  end

  describe '#next?' do
    it 'defaults to true' do
      expect(performer.next?).to eq true
    end

    it 'returns the result of the filter and state' do
      filter = ->(state) { "more #{state}" }
      performer = described_class.new(target, :the_method, filter: filter)
      expect(performer.next?("state")).to eq "more state"
    end
  end

  describe '#name' do
    it 'is assignable' do
      performer = described_class.new(target, :the_method, name: 'test-performer')
      expect(performer.name).to eq 'test-performer'
    end
  end
end
