# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::LatencyChart do
  subject(:chart) { described_class.new(GoodJob::JobsFilter.new({})) }

  describe "#data" do
    it "returns a hash of chart configuration and data" do
      puts chart.data
      expect(chart.data).to be_a(Hash)
    end
  end
end
