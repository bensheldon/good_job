# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::PerformanceIndexChart do
  subject(:chart) { described_class.new(params) }

  let(:params) { {} }

  describe "#data" do
    around do |example|
      Timecop.freeze(Time.zone.parse("2024-01-01 12:34:00 UTC"), &example)
    end

    it "returns time-series chart metadata" do
      data = chart.data

      expect(data.dig(:goodJob, :range_key)).to eq("24h")
      expect(data.dig(:goodJob, :custom_range)).to be(false)
      expect(data.dig(:goodJob, :default_range)).to be(true)
      expect(data.dig(:goodJob, :start_label)).to eq("Dec 31, 12:34")
      expect(data.dig(:goodJob, :end_label)).to eq("Jan 1, 12:34")
      expect(data.dig(:goodJob, :interval_seconds)).to eq(1.hour.to_i)
      expect(data.dig(:data, :labels).count).to eq(25)
    end

    context "with a shorter chart range" do
      let(:params) { { chart_range: "1h" } }

      it "uses more granular buckets" do
        data = chart.data

        expect(data.dig(:goodJob, :range_key)).to eq("1h")
        expect(data.dig(:goodJob, :interval_seconds)).to eq(5.minutes.to_i)
        expect(data.dig(:data, :labels).count).to eq(13)
      end
    end
  end
end
