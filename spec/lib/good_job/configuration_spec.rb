# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::Configuration do
  describe '#execution_mode' do
    it 'defaults to :external' do
      configuration = described_class.new({})
      expect(configuration.execution_mode).to eq :external
    end

    context 'when an explicit default is passed' do
      it 'falls back to the default' do
        configuration = described_class.new({})
        expect(configuration.execution_mode(default: :truck)).to eq :truck
      end
    end
  end
end
