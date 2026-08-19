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
