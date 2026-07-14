# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::PerformanceIndexChart do
  subject(:chart) { described_class.new(range) }

  let(:range) { GoodJob::PerformanceRange.new(params) }
  let(:params) { {} }

  describe "#data" do
    around do |example|
      Timecop.freeze(Time.zone.parse("2024-01-01 12:34:00 UTC"), &example)
    end

    it "returns time-series chart metadata for the default range" do
      data = chart.data

      expect(data.dig(:goodJob, :time_series)).to be(true)
      expect(data.dig(:goodJob, :interval_seconds)).to eq(1.hour.to_i)
      expect(data.dig(:goodJob, :timestamps).count).to eq(25)
      expect(data.dig(:data, :labels).count).to eq(25)
    end

    context "with a shorter chart range" do
      let(:params) { { chart_range: "1h" } }

      it "uses more granular buckets" do
        data = chart.data

        expect(range.key).to eq("1h")
        expect(range.interval_seconds).to eq(5.minutes.to_i)
        expect(data.dig(:data, :labels).count).to eq(13)
      end
    end

    context "with a non-whole-hour custom range" do
      let(:params) do
        {
          chart_start: "2024-01-01T10:03:17Z",
          chart_end: "2024-01-01T11:07:42Z",
        }
      end

      before do
        create_execution(job_class: "BeforeStart", scheduled_at: range.start_time - 1.second)
        create_execution(job_class: "AtStart", scheduled_at: range.start_time)
        create_execution(job_class: "BeforeEnd", scheduled_at: range.end_time - 1.second)
        create_execution(job_class: "AtEnd", scheduled_at: range.end_time)
        create_execution(job_class: "AfterEnd", scheduled_at: range.end_time + 1.second)
      end

      it "buckets records without widening the half-open range" do
        data = chart.data

        expect(data.dig(:data, :datasets).pluck(:label)).to contain_exactly("AtStart", "BeforeEnd")
        expect(data.dig(:goodJob, :timestamps).first).to eq("2024-01-01T10:00:00Z")
        expect(data.dig(:goodJob, :timestamps).last).to eq("2024-01-01T11:05:00Z")
        expect(data.dig(:data, :labels).count).to eq(14)
      end
    end
  end

  def create_execution(job_class:, scheduled_at:)
    GoodJob::Execution.create!(
      active_job_id: SecureRandom.uuid,
      created_at: scheduled_at,
      duration: 1.second,
      job_class: job_class,
      queue_name: "default",
      scheduled_at: scheduled_at,
      serialized_params: {},
      updated_at: scheduled_at
    )
  end
end
