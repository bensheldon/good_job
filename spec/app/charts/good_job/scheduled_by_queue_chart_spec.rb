# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::ScheduledByQueueChart do
  subject(:chart) { described_class.new(GoodJob::JobsFilter.new(params)) }

  let(:params) { {} }

  describe "#data" do
    around do |example|
      Timecop.freeze(Time.zone.parse("2024-01-01 12:34:00 UTC"), &example)
    end

    it "returns a hash of chart configuration and data" do
      expect(chart.data).to be_a(Hash)
    end

    it "defaults to the last 24 hours with hourly buckets" do
      data = chart.data

      expect(data.dig(:goodJob, :range_key)).to eq("24h")
      expect(data.dig(:goodJob, :custom_range)).to be(false)
      expect(data.dig(:goodJob, :default_range)).to be(true)
      expect(data.dig(:goodJob, :start_label)).to eq("Dec 31, 12:34")
      expect(data.dig(:goodJob, :end_label)).to eq("Jan 1, 12:34")
      expect(data.dig(:goodJob, :interval_seconds)).to eq(1.hour.to_i)
      expect(data.dig(:data, :labels).count).to eq(25)
    end

    context "with a preset chart range" do
      let(:params) { { chart_range: "1h" } }

      it "uses the preset bucket interval" do
        data = chart.data

        expect(data.dig(:goodJob, :range_key)).to eq("1h")
        expect(data.dig(:goodJob, :default_range)).to be(false)
        expect(data.dig(:goodJob, :interval_seconds)).to eq(5.minutes.to_i)
        expect(data.dig(:data, :labels).count).to eq(13)
      end
    end

    context "with a custom chart range" do
      let(:params) do
        {
          chart_start: "2024-01-01T10:00:00Z",
          chart_end: "2024-01-01T11:00:00Z",
        }
      end

      it "uses the custom range without selecting a preset" do
        data = chart.data

        expect(data.dig(:goodJob, :range_key)).to be_nil
        expect(data.dig(:goodJob, :custom_range)).to be(true)
        expect(data.dig(:goodJob, :default_range)).to be(false)
        expect(data.dig(:goodJob, :start_label)).to eq("Jan 1, 10:00")
        expect(data.dig(:goodJob, :end_label)).to eq("Jan 1, 11:00")
        expect(data.dig(:goodJob, :interval_seconds)).to eq(5.minutes.to_i)
        expect(data.dig(:data, :labels).count).to eq(13)
      end
    end
  end
end
