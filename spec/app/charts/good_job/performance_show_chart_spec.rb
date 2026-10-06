# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoodJob::PerformanceShowChart do
  describe "#data" do
    it "filters the histogram with the shared half-open range" do
      range = GoodJob::PerformanceRange.new(
        chart_start: "2024-01-01T10:03:17Z",
        chart_end: "2024-01-01T11:07:42Z"
      )

      create_execution(job_class: "ExampleJob", scheduled_at: range.start_time - 1.second)
      create_execution(job_class: "ExampleJob", scheduled_at: range.start_time)
      create_execution(job_class: "ExampleJob", scheduled_at: range.end_time - 1.second)
      create_execution(job_class: "ExampleJob", scheduled_at: range.end_time)
      create_execution(job_class: "OtherJob", scheduled_at: range.start_time)

      data = described_class.new("ExampleJob", range).data

      expect(data.dig(:data, :datasets, 0, :data).sum).to eq(2)
    end

    it "buckets each metric on its own measurement" do
      range = GoodJob::PerformanceRange.new(
        chart_start: "2024-01-01T10:03:17Z",
        chart_end: "2024-01-01T11:07:42Z"
      )

      # 1s of runtime after a 12s wait: 1s, 12s and their 13s total each fall in a
      # different bucket, so the three histograms cannot coincide.
      create_execution(job_class: "ExampleJob", scheduled_at: range.start_time, queue_time: 12.seconds)

      histograms = GoodJob::LatencyMetric.options.to_h do |metric|
        [metric.key, described_class.new("ExampleJob", range, metric).data]
      end
      buckets = histograms.transform_values do |data|
        data.dig(:data, :labels)[data.dig(:data, :datasets, 0, :data).index(1)]
      end

      expect(histograms.transform_values { |data| data.dig(:options, :plugins, :title, :text) })
        .to eq(execution: "Execution latency", queue: "Queue latency", total: "Total latency")
      expect(buckets).to eq(execution: "1.1s", queue: "13s", total: "20s")
    end
  end

  def create_execution(job_class:, scheduled_at:, queue_time: 0)
    GoodJob::Execution.create!(
      active_job_id: SecureRandom.uuid,
      created_at: scheduled_at + queue_time,
      duration: 1.second,
      job_class: job_class,
      queue_name: "default",
      scheduled_at: scheduled_at,
      serialized_params: {},
      updated_at: scheduled_at
    )
  end
end
