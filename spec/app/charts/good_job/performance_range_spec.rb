# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoodJob::PerformanceRange do
  around do |example|
    Timecop.freeze(Time.zone.parse("2024-01-01 12:34:56 UTC"), &example)
  end

  describe "range resolution" do
    it "defaults to a canonical last-24-hours range" do
      range = described_class.new

      expect(range.key).to eq("24h")
      expect(range.start_time).to eq(Time.zone.parse("2023-12-31 12:34:56 UTC"))
      expect(range.end_time).to eq(Time.zone.parse("2024-01-01 12:34:56 UTC"))
      expect(range.start_label).to eq("Dec 31, 12:34:56")
      expect(range.end_label).to eq("Jan 1, 12:34:56")
      expect(range.to_params).to eq({})
      expect(range.navigation_params).to eq(
        "chart_range" => "24h",
        "chart_start" => "2023-12-31T12:34:56Z",
        "chart_end" => "2024-01-01T12:34:56Z"
      )
      expect(range).to be_default
    end

    it "resolves a preset to canonical page state" do
      range = described_class.new(chart_range: "1h")

      expect(range.key).to eq("1h")
      expect(range.interval_seconds).to eq(5.minutes.to_i)
      expect(range.start_time).to eq(Time.zone.parse("2024-01-01 11:34:56 UTC"))
      expect(range.to_params).to eq("chart_range" => "1h")
      expect(range).not_to be_default
    end

    it "preserves a valid anchored preset's exact bounds and identity" do
      range = described_class.new(
        chart_range: "1h",
        chart_start: "2024-01-01T10:03:17Z",
        chart_end: "2024-01-01T11:03:17Z"
      )

      expect(range.key).to eq("1h")
      expect(range.start_time).to eq(Time.zone.parse("2024-01-01 10:03:17 UTC"))
      expect(range.end_time).to eq(Time.zone.parse("2024-01-01 11:03:17 UTC"))
      expect(range.interval_seconds).to eq(5.minutes.to_i)
      expect(range.to_params).to eq(
        "chart_range" => "1h",
        "chart_start" => "2024-01-01T10:03:17Z",
        "chart_end" => "2024-01-01T11:03:17Z"
      )
      expect(range.navigation_params).to eq(range.to_params)
    end

    it "drops an inconsistent anchored preset identity while preserving its safe custom bounds" do
      parameters = {
        chart_range: "1h",
        chart_start: "2024-01-01T10:03:17Z",
        chart_end: "2024-01-01T12:03:17Z",
      }
      range = described_class.new(parameters)

      expect(range.key).to be_nil
      expect(range.start_time).to eq(Time.zone.parse("2024-01-01 10:03:17 UTC"))
      expect(range.end_time).to eq(Time.zone.parse("2024-01-01 12:03:17 UTC"))
      expect(range.to_params).to eq(
        "chart_start" => "2024-01-01T10:03:17Z",
        "chart_end" => "2024-01-01T12:03:17Z"
      )
      expect(range.canonical_parameters?(parameters.stringify_keys)).to be(false)
    end

    it "keeps the 24-hour preset at 24 elapsed hours across spring DST" do
      Time.use_zone("America/New_York") do
        Timecop.freeze(Time.zone.parse("2024-03-11 00:00:00")) do
          range = described_class.new(chart_range: "24h")

          expect(range.start_time.iso8601).to eq("2024-03-09T23:00:00-05:00")
          expect(range.end_time.iso8601).to eq("2024-03-11T00:00:00-04:00")
          expect(range.end_time - range.start_time).to eq(24.hours.to_i)

          anchored_range = described_class.new(range.navigation_params.symbolize_keys)
          expect(anchored_range.key).to eq("24h")
          expect(anchored_range.start_time).to eq(range.start_time)
          expect(anchored_range.end_time).to eq(range.end_time)
        end
      end
    end

    it "keeps the 24-hour preset at 24 elapsed hours across fall DST" do
      Time.use_zone("America/New_York") do
        Timecop.freeze(Time.zone.parse("2024-11-04 00:00:00")) do
          range = described_class.new(chart_range: "24h")

          expect(range.start_time.iso8601).to eq("2024-11-03T01:00:00-04:00")
          expect(range.end_time.iso8601).to eq("2024-11-04T00:00:00-05:00")
          expect(range.end_time - range.start_time).to eq(24.hours.to_i)
        end
      end
    end

    it "includes current-second executions while keeping a second-precise displayed bound" do
      Timecop.freeze(Time.zone.parse("2024-01-01 12:34:56.500 UTC")) do
        scheduled_at = Time.current
        range = described_class.new(chart_range: "1h")
        create_execution(job_class: "CurrentSecond", scheduled_at: scheduled_at)

        expect(range.end_time).to eq(Time.zone.parse("2024-01-01 12:34:57 UTC"))
        expect(range.end_label).to eq("Jan 1, 12:34:57")
        expect(range.apply(GoodJob::Execution).pluck(:job_class)).to include("CurrentSecond")
      end
    end

    it "canonicalizes a non-whole-hour custom range without widening its query bounds" do
      range = described_class.new(
        chart_start: "2024-01-01T10:03:17.123Z",
        chart_end: "2024-01-01T11:07:42.987Z"
      )

      expect(range.start_time).to eq(Time.zone.parse("2024-01-01 10:03:17 UTC"))
      expect(range.end_time).to eq(Time.zone.parse("2024-01-01 11:07:42 UTC"))
      expect(range.start_label).to eq("Jan 1, 10:03:17")
      expect(range.end_label).to eq("Jan 1, 11:07:42")
      expect(range.to_params).to eq(
        "chart_start" => "2024-01-01T10:03:17Z",
        "chart_end" => "2024-01-01T11:07:42Z"
      )
      expect(range.time_series_binds.map(&:value)).to eq([
                                                           Time.zone.parse("2024-01-01 10:00:00 UTC"),
                                                           Time.zone.parse("2024-01-01 11:05:00 UTC"),
                                                           5.minutes.to_i,
                                                         ])
    end

    it "falls back to default state for non-scalar, non-finite, non-strict, extreme, and incomplete inputs" do
      invalid_parameters = [
        { chart_start: ["2024-01-01T10:00:00Z"], chart_end: "2024-01-01T11:00:00Z" },
        { chart_start: { value: "2024-01-01T10:00:00Z" }, chart_end: "2024-01-01T11:00:00Z" },
        { chart_start: 1, chart_end: "2024-01-01T11:00:00Z" },
        { chart_start: "NaN", chart_end: "Infinity" },
        { chart_start: "2024-01-01 10:00:00 UTC", chart_end: "2024-01-01T11:00:00Z" },
        { chart_start: "0999-12-31T23:59:59Z", chart_end: "1000-01-01T00:00:01Z" },
        { chart_start: "9999-12-31T23:59:58Z", chart_end: "10000-01-01T00:00:00Z" },
        { chart_start: "not-a-time", chart_end: "2024-01-01T11:00:00Z" },
        { chart_start: "2024-01-01T10:00:00Z" },
        { chart_start: "2024-01-01T11:00:00Z", chart_end: "2024-01-01T10:00:00Z" },
        { chart_range: ["1h"] },
        { chart_range: { value: "1h" } },
        { chart_range: "unknown" },
      ]

      invalid_parameters.each do |parameters|
        range = described_class.new(parameters)

        expect(range.key).to eq("24h")
        expect(range.to_params).to eq({})
        expect(range).to be_default
        expect(range.canonical_parameters?(parameters.stringify_keys)).to be(false)
      end
    end

    it "rejects repeated scalar timestamp parameters from a raw query" do
      query_string = URI.encode_www_form([
                                           ["chart_start", "2024-01-01T10:00:00Z"],
                                           ["chart_start", "2024-01-01T10:30:00Z"],
                                           ["chart_end", "2024-01-01T11:00:00Z"],
                                         ])
      range = described_class.new(
        {
          chart_start: "2024-01-01T10:30:00Z",
          chart_end: "2024-01-01T11:00:00Z",
        },
        query_string: query_string
      )

      expect(range.key).to eq("24h")
      expect(range.to_params).to eq({})
      expect(range).to be_default
    end

    it "drops a repeated preset identity while retaining valid absolute bounds" do
      query_string = URI.encode_www_form([
                                           ["chart_range", "1h"],
                                           ["chart_range", "1h"],
                                           ["chart_start", "2024-01-01T10:00:00Z"],
                                           ["chart_end", "2024-01-01T11:00:00Z"],
                                         ])
      range = described_class.new(
        {
          chart_range: "1h",
          chart_start: "2024-01-01T10:00:00Z",
          chart_end: "2024-01-01T11:00:00Z",
        },
        query_string: query_string
      )

      expect(range.key).to be_nil
      expect(range.to_params).to eq(
        "chart_start" => "2024-01-01T10:00:00Z",
        "chart_end" => "2024-01-01T11:00:00Z"
      )
    end

    it "uses a valid preset while removing partial custom parameters" do
      range = described_class.new(chart_range: "6h", chart_start: "2024-01-01T10:00:00Z")

      expect(range.key).to eq("6h")
      expect(range.to_params).to eq("chart_range" => "6h")
    end

    it "clamps over-maximum custom input and exposes canonical bounds" do
      range = described_class.new(
        chart_start: "2023-01-01T00:00:00Z",
        chart_end: "2024-01-01T00:00:00Z"
      )

      expect(range.start_time).to eq(Time.zone.parse("2023-12-01 00:00:00 UTC"))
      expect(range.end_time).to eq(Time.zone.parse("2024-01-01 00:00:00 UTC"))
      expect(range.to_params).to eq(
        "chart_start" => "2023-12-01T00:00:00Z",
        "chart_end" => "2024-01-01T00:00:00Z"
      )
    end

    it "clamps fall-DST input to exactly 31 elapsed days and selects a final interval" do
      Time.use_zone("America/New_York") do
        range = described_class.new(
          chart_start: "2024-09-01T00:00:00-04:00",
          chart_end: "2024-11-04T00:00:00-05:00"
        )

        expect(range.start_time.iso8601).to eq("2024-10-04T01:00:00-04:00")
        expect(range.end_time.iso8601).to eq("2024-11-04T00:00:00-05:00")
        expect(range.end_time - range.start_time).to eq((24.hours * 31).to_i)
        expect(range.interval_seconds).to eq(6.hours.to_i)
        expect(range.to_params).to eq(
          "chart_start" => "2024-10-04T01:00:00-04:00",
          "chart_end" => "2024-11-04T00:00:00-05:00"
        )
      end
    end
  end

  describe "#apply" do
    it "uses the same half-open boundary at just-before, at, and just-after instants" do
      start_time = Time.zone.parse("2024-01-01 10:03:17 UTC")
      end_time = Time.zone.parse("2024-01-01 11:07:42 UTC")
      range = described_class.new(chart_start: start_time.iso8601, chart_end: end_time.iso8601)

      {
        "before-start" => start_time - 1.second,
        "at-start" => start_time,
        "before-end" => end_time - 1.second,
        "at-end" => end_time,
        "after-end" => end_time + 1.second,
      }.each do |job_class, scheduled_at|
        create_execution(job_class: job_class, scheduled_at: scheduled_at)
      end

      expect(range.apply(GoodJob::Execution).order(:scheduled_at).pluck(:job_class)).to eq(%w[at-start before-end])
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
