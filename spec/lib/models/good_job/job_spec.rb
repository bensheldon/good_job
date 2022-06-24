# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::Job do
  describe '#initialize' do
    it 'is deprecated' do
      allow(ActiveSupport::Deprecation).to receive(:warn)
      described_class.create!
      expect(ActiveSupport::Deprecation).to have_received(:warn)
    end
  end
end
