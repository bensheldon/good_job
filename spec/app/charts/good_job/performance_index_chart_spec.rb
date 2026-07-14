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

    context "with a sub-minute custom range" do
      let(:params) do
        {
          chart_start: "2024-01-01T10:00:01Z",
          chart_end: "2024-01-01T10:00:46Z",
        }
      end

      it "plots second-precise labels at the exact bounded coordinate count" do
        data = chart.data

        expect(range.interval_seconds).to eq(2.seconds.to_i)
        expect(range.label_style).to eq("time_seconds")
        expect(data.dig(:goodJob, :timestamps).count).to eq(range.time_series_coordinate_count)
        expect(data.dig(:goodJob, :timestamps).count).to be <= GoodJob::PerformanceRange::MAXIMUM_TIME_SERIES_COORDINATES
        expect(data.dig(:data, :labels)).to all(match(/\A\d{2}:\d{2}:\d{2}\z/))
      end
    end

    context "with a 20-year custom range" do
      let(:params) do
        {
          chart_start: "2004-01-01T00:00:00Z",
          chart_end: "2024-01-01T00:00:00Z",
        }
      end

      it "uses fixed elapsed year-scale buckets with year-precise labels" do
        data = chart.data

        expect(range.interval_seconds).to eq(365.days.to_i)
        expect(range.label_style).to eq("date_time_year")
        expect(data.dig(:goodJob, :timestamps).count).to eq(range.time_series_coordinate_count)
        expect(data.dig(:goodJob, :timestamps).count).to be <= GoodJob::PerformanceRange::MAXIMUM_TIME_SERIES_COORDINATES
        expect(data.dig(:data, :labels)).to all(match(/\b\d{4}\b/))
      end
    end

    context "with a range across a repeated fall-back hour" do
      let(:params) do
        {
          chart_start: "2024-11-03T00:45:00-04:00",
          chart_end: "2024-11-03T01:45:00-05:00",
        }
      end

      it "adds offsets only to otherwise duplicate server-rendered labels" do
        Time.use_zone("America/New_York") do
          labels = chart.data.dig(:data, :labels)

          expect(labels).to include("00:45")
          expect(labels).to include("01:00 -04:00", "01:00 -05:00")
          expect(labels.grep(/ -0[45]:00\z/)).not_to be_empty
          expect(labels.grep(/ -0[45]:00\z/).length).to be < labels.length
        end
      end
    end

    context "with the widest four-digit custom range" do
      let(:params) do
        {
          chart_start: "1000-01-01T00:00:00Z",
          chart_end: "9999-12-31T23:59:59Z",
        }
      end

      it "executes the bigint interval series without exceeding the coordinate bound" do
        data = chart.data

        expect(range.interval_seconds).to eq(500 * 365.days.to_i)
        expect(data.dig(:goodJob, :timestamps).count).to eq(19)
        expect(data.dig(:goodJob, :timestamps).count).to eq(range.time_series_coordinate_count)
        expect(data.dig(:goodJob, :timestamps)).to all(match(GoodJob::PerformanceRange::TIMESTAMP_PATTERN))
      end
    end

    context "when the native range reaches the four-digit upper bound in a negative-offset timezone" do
      let(:params) do
        {
          chart_start: "9999-12-31T23:54:59",
          chart_end: "9999-12-31T23:59:59",
        }
      end

      it "emits draggable boundaries in the strict canonical parameter grammar" do
        Time.use_zone("America/Toronto") do
          metadata = chart.data.fetch(:goodJob)
          draggable_boundaries = metadata.fetch_values(:range_start, :range_end) + metadata.fetch(:timestamps)

          expect(draggable_boundaries).to all(match(GoodJob::PerformanceRange::TIMESTAMP_PATTERN))
          expect(metadata.fetch(:range_end)).to eq("9999-12-31T23:59:59-05:00")
          expect(draggable_boundaries).not_to include(a_string_starting_with("+010000"))
        end
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
