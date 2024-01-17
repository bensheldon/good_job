# frozen_string_literal: true

require 'rails_helper'

describe JobIteration::Integrations::GoodJob do
  it 'sets up the interruption adapter' do
    expect(JobIteration.interruption_adapter).to eq(described_class)
  end

  describe '.call' do
    context 'when GoodJob is shutting down' do
      before { allow(GoodJob).to receive(:shutdown?).and_return(true) }

      it 'returns true' do
        expect(described_class.call).to be(true)
      end
    end

    context 'when GoodJob is not shutting down' do
      before { allow(GoodJob).to receive(:shutdown?).and_return(false) }

      it 'returns false' do
        expect(described_class.call).to be(false)
      end
    end
  end
end
