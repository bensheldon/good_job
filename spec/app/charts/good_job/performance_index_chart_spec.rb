# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::PerformanceIndexChart do
  subject(:chart) { described_class.new }

  describe "#data" do
    it "returns a hash of chart configuration and data" do
      expect(chart.data).to be_a(Hash)
    end

    it "only aggregates executions scheduled within the chart's 24-hour window" do
      GoodJob::Execution.create!(
        active_job_id: SecureRandom.uuid,
        job_class: "InWindowJob",
        scheduled_at: 2.hours.ago,
        duration: 5.seconds
      )
      GoodJob::Execution.create!(
        active_job_id: SecureRandom.uuid,
        job_class: "OutOfWindowJob",
        scheduled_at: 40.days.ago,
        duration: 100.seconds
      )

      labels = chart.data[:data][:datasets].pluck(:label)

      expect(labels).to include("InWindowJob")
      expect(labels).not_to include("OutOfWindowJob")
    end
  end
end
