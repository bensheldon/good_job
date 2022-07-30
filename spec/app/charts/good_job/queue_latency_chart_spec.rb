# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GoodJob::QueueLatencyChart do
  subject(:chart) { described_class.new(GoodJob::JobsFilter.new({})) }

  describe "#data" do
    before do
      GoodJob::Execution.create(created_at: 90.seconds.ago,
                                scheduled_at: 75.seconds.ago,
                                performed_at: 60.seconds.ago,
                                finished_at: 45.seconds.ago
      )
    end

    it "returns a hash of chart configuration and data" do
      result = chart.data
      puts result
      expect(result).to be_a(Array)
      expect([120, 121].include? result.size).to be true
      expect(result.first).to include(
                                "timestamp" => a_kind_of(Time),
                                "queue_latency_min" => a_kind_of(NilClass),
                              )
      expect(result.count { |row| row["queue_latency_avg"].present? }).to eq 1
    end
  end
end
