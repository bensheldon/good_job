# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::ProbeServer::NotFoundApp do
  describe '#call' do
    it 'returns "Not Found"' do
      response = described_class.call("")
      expect(response[0]).to eq(404)
    end
  end
end
