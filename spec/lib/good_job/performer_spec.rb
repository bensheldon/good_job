require 'rails_helper'

RSpec.describe GoodJob::Performer do
  let(:target) { double('The Target', the_method: nil) } # rubocop:disable RSpec/VerifiedDoubles

  describe '#next' do
    it 'delegates to target#method_name' do
      performer = described_class.new(target, :the_method)
      performer.next

      expect(target).to have_received(:the_method)
    end
  end

  describe '#name' do
    it 'is assignable' do
      performer = described_class.new(target, :the_method, name: 'test-performer')
      expect(performer.name).to eq 'test-performer'
    end
  end
end
