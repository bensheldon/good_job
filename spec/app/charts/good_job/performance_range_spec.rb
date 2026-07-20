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
      expect(range.start_local_value).to eq("2023-12-31T12:34:56")
      expect(range.end_local_value).to eq("2024-01-01T12:34:56")
      expect(range.to_params).to eq({})
      expect(range.navigation_params).to eq(
        "chart_range" => "24h",
        "chart_start" => "2023-12-31T12:34:56Z",
        "chart_end" => "2024-01-01T12:34:56Z"
      )
      expect(range.custom_params).to eq(
        "chart_start" => "2023-12-31T12:34:56Z",
        "chart_end" => "2024-01-01T12:34:56Z"
      )
      expect(range.reload_params).to eq({})
      expect(range).to be_default
    end

    it "resolves a preset to canonical page state" do
      range = described_class.new(chart_range: "1h")

      expect(range.key).to eq("1h")
      expect(range.interval_seconds).to eq(5.minutes.to_i)
      expect(range.start_time).to eq(Time.zone.parse("2024-01-01 11:34:56 UTC"))
      expect(range.to_params).to eq("chart_range" => "1h")
      expect(range.reload_params).to eq("chart_range" => "1h")
      expect(range).not_to be_default
    end

    it "preserves every preset's established resolution" do
      {
        "1h" => 5.minutes,
        "6h" => 15.minutes,
        "24h" => 1.hour,
        "7d" => 6.hours,
      }.each do |key, interval|
        range = described_class.new(chart_range: key)

        expect(range.interval_seconds).to eq(interval.to_i)
        expect(range.time_series_coordinate_count).to be <= described_class::MAXIMUM_TIME_SERIES_COORDINATES
      end
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
      expect(range.custom_params).to eq(
        "chart_start" => "2024-01-01T10:03:17Z",
        "chart_end" => "2024-01-01T11:03:17Z"
      )
      expect(range.reload_params).to eq("chart_range" => "1h")
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
      expect(range.reload_params).to eq(range.to_params)
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

    it "interprets native local values in the page timezone and canonicalizes them once" do
      Time.use_zone("America/St_Johns") do
        submitted_parameters = {
          "chart_start" => "2024-01-01T10:03:17",
          "chart_end" => "2024-01-01T11:07",
        }
        range = described_class.new(submitted_parameters.symbolize_keys)

        expect(range.start_time.iso8601).to eq("2024-01-01T10:03:17-03:30")
        expect(range.end_time.iso8601).to eq("2024-01-01T11:07:00-03:30")
        expect(range.start_local_value).to eq("2024-01-01T10:03:17")
        expect(range.end_local_value).to eq("2024-01-01T11:07:00")
        expect(range.to_params).to eq(
          "chart_start" => "2024-01-01T10:03:17-03:30",
          "chart_end" => "2024-01-01T11:07:00-03:30"
        )
        expect(range.canonical_parameters?(submitted_parameters)).to be(false)

        canonical_range = described_class.new(range.to_params.symbolize_keys)
        expect(canonical_range.canonical_parameters?(range.to_params)).to be(true)
        expect(canonical_range.start_time).to eq(range.start_time)
        expect(canonical_range.end_time).to eq(range.end_time)
      end
    end

    it "resolves edited local values in a validated browser timezone and strips transient state" do
      Time.use_zone("UTC") do
        submitted_parameters = {
          "chart_start" => "2024-01-01T10:03:17",
          "chart_end" => "2024-01-01T11:07:42",
          "chart_time_zone" => "America/St_Johns",
        }
        range = described_class.new(submitted_parameters.symbolize_keys)

        expect(range.start_time).to eq(Time.iso8601("2024-01-01T10:03:17-03:30"))
        expect(range.end_time).to eq(Time.iso8601("2024-01-01T11:07:42-03:30"))
        expect(range.to_params).to eq(
          "chart_start" => "2024-01-01T13:33:17Z",
          "chart_end" => "2024-01-01T14:37:42Z"
        )
        expect(range.canonical_parameters?(submitted_parameters)).to be(false)
      end
    end

    it "uses browser-zone gap and fold rules independently of the application timezone" do
      Time.use_zone("UTC") do
        gap = described_class.new(
          chart_start: "2024-03-10T02:30:00",
          chart_end: "2024-03-10T04:00:00",
          chart_time_zone: "America/New_York"
        )
        fold = described_class.new(
          chart_start: "2024-11-03T01:15:00",
          chart_end: "2024-11-03T01:45:00",
          chart_time_zone: "America/New_York"
        )

        expect(gap).to be_default
        expect(fold.start_time).to eq(Time.iso8601("2024-11-03T01:15:00-04:00"))
        expect(fold.end_time).to eq(Time.iso8601("2024-11-03T01:45:00-05:00"))
        expect(fold.end_time - fold.start_time).to eq(90.minutes.to_i)
      end
    end

    it "rejects invalid, oversized, structured, and repeated browser timezone state" do
      base_parameters = {
        chart_start: "2024-01-01T10:03:17",
        chart_end: "2024-01-01T11:07:42",
      }
      invalid_values = [
        "Missing/Zone",
        "A" * (described_class::MAXIMUM_TIME_ZONE_LENGTH + 1),
        ["America/Toronto"],
        { name: "America/Toronto" },
      ]

      invalid_values.each do |value|
        expect(described_class.new(**base_parameters, chart_time_zone: value)).to be_default
      end

      exact = described_class.new(
        chart_start: "2024-01-01T10:03:17Z",
        chart_end: "2024-01-01T11:07:42Z",
        chart_time_zone: "Missing/Zone"
      )
      expect(exact.to_params).to eq(
        "chart_start" => "2024-01-01T10:03:17Z",
        "chart_end" => "2024-01-01T11:07:42Z"
      )
      exact_with_zone = {
        "chart_start" => "2024-01-01T10:03:17Z",
        "chart_end" => "2024-01-01T11:07:42Z",
        "chart_time_zone" => "Missing/Zone",
      }
      expect(exact.canonical_parameters?(exact_with_zone)).to be(false)

      query_string = URI.encode_www_form([
                                           ["chart_start", base_parameters.fetch(:chart_start)],
                                           ["chart_end", base_parameters.fetch(:chart_end)],
                                           ["chart_time_zone", "America/Toronto"],
                                           ["chart_time_zone", "UTC"],
                                         ])
      repeated = described_class.new(
        base_parameters.merge(chart_time_zone: "UTC"),
        query_string: query_string
      )

      expect(repeated).to be_default
    end

    it "rejects nonexistent local times and explicitly spans both fall-back occurrences" do
      Time.use_zone("America/New_York") do
        [
          { chart_start: "2024-03-10T02:30:00", chart_end: "2024-03-10T04:00:00" },
          { chart_start: "2024-03-10T01:00:00", chart_end: "2024-03-10T02:30:00" },
        ].each do |parameters|
          expect(described_class.new(parameters)).to be_default
        end

        range = described_class.new(
          chart_start: "2024-11-03T01:15:00",
          chart_end: "2024-11-03T01:45:00"
        )

        expect(range.start_time.iso8601).to eq("2024-11-03T01:15:00-04:00")
        expect(range.end_time.iso8601).to eq("2024-11-03T01:45:00-05:00")
        expect(range.end_time - range.start_time).to eq(90.minutes.to_i)
        expect(range.start_label).to eq("Nov 3, 01:15:00 -04:00")
        expect(range.end_label).to eq("Nov 3, 01:45:00 -05:00")
      end
    end

    it "uses date-inclusive chart labels for a custom range of exactly 24 elapsed hours" do
      range = described_class.new(
        chart_start: "2024-01-01T10:00:00Z",
        chart_end: "2024-01-02T10:00:00Z"
      )

      expect(range.key).to be_nil
      expect(range.label_style).to eq("date_time")
      expect(range.chart_timestamp_label(range.start_time)).to eq("Jan 1 10:00")
      expect(range.chart_timestamp_label(range.end_time)).to eq("Jan 2 10:00")
    end

    it "includes years in long custom endpoint labels" do
      range = described_class.new(
        chart_start: "2004-07-01T00:00:00Z",
        chart_end: "2024-07-01T00:00:00Z"
      )

      expect(range.start_label).to eq("Jul 1, 2004 00:00:00")
      expect(range.end_label).to eq("Jul 1, 2024 00:00:00")
    end

    it "does not add endpoint offsets when a full-year range has equal endpoint offsets" do
      Time.use_zone("America/New_York") do
        range = described_class.new(
          chart_start: "2023-01-01T00:00:00-05:00",
          chart_end: "2024-01-01T00:00:00-05:00"
        )

        expect(range.start_label).to eq("Jan 1, 2023 00:00:00")
        expect(range.end_label).to eq("Jan 1, 2024 00:00:00")
      end
    end

    it "round-trips the native four-digit-year bounds in a non-UTC timezone" do
      Time.use_zone("America/Toronto") do
        minimum_range = described_class.new(
          chart_start: "1000-01-01T00:00:00",
          chart_end: "1000-01-01T00:00:01"
        )
        maximum_range = described_class.new(
          chart_start: "9999-12-31T23:59:58",
          chart_end: "9999-12-31T23:59:59"
        )

        [minimum_range, maximum_range].each do |range|
          canonical_range = described_class.new(range.to_params.symbolize_keys)

          expect(canonical_range.canonical_parameters?(range.to_params)).to be(true)
          expect(canonical_range.start_local_value).to eq(range.start_local_value)
          expect(canonical_range.end_local_value).to eq(range.end_local_value)
        end
      end
    end

    it "falls back to default state for non-scalar, non-finite, non-strict, extreme, and incomplete inputs" do
      invalid_parameters = [
        { chart_start: ["2024-01-01T10:00:00Z"], chart_end: "2024-01-01T11:00:00Z" },
        { chart_start: { value: "2024-01-01T10:00:00Z" }, chart_end: "2024-01-01T11:00:00Z" },
        { chart_start: 1, chart_end: "2024-01-01T11:00:00Z" },
        { chart_start: "NaN", chart_end: "Infinity" },
        { chart_start: "2024-01-01 10:00:00 UTC", chart_end: "2024-01-01T11:00:00Z" },
        { chart_start: "2024-02-30T10:00:00", chart_end: "2024-02-30T11:00:00" },
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

    it "preserves custom input longer than 31 days without truncating its canonical bounds" do
      range = described_class.new(
        chart_start: "2023-01-01T00:00:00Z",
        chart_end: "2024-01-01T00:00:00Z"
      )

      expect(range.start_time).to eq(Time.zone.parse("2023-01-01 00:00:00 UTC"))
      expect(range.end_time).to eq(Time.zone.parse("2024-01-01 00:00:00 UTC"))
      expect(range.interval_seconds).to eq(14.days.to_i)
      expect(range.to_params).to eq(
        "chart_start" => "2023-01-01T00:00:00Z",
        "chart_end" => "2024-01-01T00:00:00Z"
      )
    end

    it "preserves a long fall-DST range as fixed elapsed time" do
      Time.use_zone("America/New_York") do
        range = described_class.new(
          chart_start: "2024-09-01T00:00:00-04:00",
          chart_end: "2024-11-04T00:00:00-05:00"
        )

        expect(range.start_time.iso8601).to eq("2024-09-01T00:00:00-04:00")
        expect(range.end_time.iso8601).to eq("2024-11-04T00:00:00-05:00")
        expect(range.end_time - range.start_time).to eq((64.days + 1.hour).to_i)
        expect(range.interval_seconds).to eq(3.days.to_i)
        expect(range.to_params).to eq(
          "chart_start" => "2024-09-01T00:00:00-04:00",
          "chart_end" => "2024-11-04T00:00:00-05:00"
        )
      end
    end

    it "selects semantic fixed intervals from seconds through long elapsed scales" do
      examples = [
        ["2024-01-01T10:00:01Z", "2024-01-01T10:00:46Z", 2.seconds],
        ["2024-01-01T10:03:17Z", "2024-01-01T12:03:17Z", 5.minutes],
        ["2024-01-01T10:03:17Z", "2024-01-03T10:03:17Z", 2.hours],
        ["2024-01-01T00:00:00Z", "2024-02-01T00:00:00Z", 2.days],
        ["2022-01-01T00:00:00Z", "2024-01-01T00:00:00Z", 30.days],
        ["2004-01-01T00:00:00Z", "2024-01-01T00:00:00Z", 365.days],
      ]

      examples.each do |start_at, end_at, expected_interval|
        range = described_class.new(chart_start: start_at, chart_end: end_at)

        expect(range.interval_seconds).to eq(expected_interval.to_i)
        expect(range.time_series_coordinate_count).to be <= described_class::MAXIMUM_TIME_SERIES_COORDINATES
      end
    end

    it "uses precise labels for sub-minute and multi-year custom ranges" do
      sub_minute_range = described_class.new(
        chart_start: "2024-01-01T10:00:01Z",
        chart_end: "2024-01-01T10:00:46Z"
      )
      multi_year_range = described_class.new(
        chart_start: "2004-01-01T00:00:00Z",
        chart_end: "2024-01-01T00:00:00Z"
      )

      expect(sub_minute_range.label_style).to eq("time_seconds")
      expect(sub_minute_range.chart_timestamp_label(sub_minute_range.start_time)).to eq("10:00:01")
      expect(multi_year_range.label_style).to eq("date_time_year")
      expect(multi_year_range.chart_timestamp_label(multi_year_range.start_time)).to eq("Jan 1, 2004 00:00")
    end

    it "falls back to the coarsest interval instead of raising when no candidate fits" do
      stub_const("#{described_class}::MAXIMUM_TIME_SERIES_COORDINATES", 0)
      range = described_class.new(
        chart_start: "1000-01-01T00:00:00Z",
        chart_end: "9999-12-31T23:59:59Z"
      )

      expect { range.interval_seconds }.not_to raise_error
      expect(range.interval_seconds).to eq(described_class::SEMANTIC_INTERVALS.last)
    end

    it "bounds the widest four-digit range with the final fixed elapsed candidate" do
      range = described_class.new(
        chart_start: "1000-01-01T00:00:00Z",
        chart_end: "9999-12-31T23:59:59Z"
      )

      expect(range.start_time).to eq(Time.iso8601("1000-01-01T00:00:00Z"))
      expect(range.end_time).to eq(Time.iso8601("9999-12-31T23:59:59Z"))
      allow(range.start_time).to receive(:to_r).and_raise("extreme rational epoch is not portable")
      expect(range.interval_seconds).to eq(500 * 365.days.to_i)
      expect(range.interval_seconds).to eq(described_class::SEMANTIC_INTERVALS.last)
      expect(range.time_series_coordinate_count).to eq(19)
      expect(range.time_series_coordinate_count).to be <= described_class::MAXIMUM_TIME_SERIES_COORDINATES
      expect(range.time_series_binds.first(2).map(&:value_for_database)).to eq(
        [Time.iso8601("0970-08-31T00:00:00Z"), Time.iso8601("9964-09-09T00:00:00Z")]
      )
      expect(range.time_series_binds.last.value_for_database).to eq(range.interval_seconds)
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
