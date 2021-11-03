# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::ScheduledByQueueChart do
  subject(:chart) { described_class.new(GoodJob::ExecutionsFilter.new({})) }

  describe "#data" do
    it "returns a hash of chart configuration and data" do
      expect(chart.data).to be_a(Hash)
    end
  end
end
