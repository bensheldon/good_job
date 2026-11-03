# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoodJob::ScheduledByQueueChart do
  subject(:chart) { described_class.new(GoodJob::JobsFilter.new({})) }

  describe "#data" do
    it "returns a hash of chart configuration and data" do
      expect(chart.data).to be_a(Hash)
    end

    it "orders the queues alphabetically, like the queue filter" do
      create_job(queue_name: "zebra", scheduled_at: 3.hours.ago)
      create_job(queue_name: "alpha", scheduled_at: 1.hour.ago)

      expect(chart.data.dig(:data, :datasets).pluck(:label)).to eq(%w[alpha zebra])
    end
  end

  def create_job(queue_name:, scheduled_at:)
    GoodJob::Job.create!(
      active_job_id: SecureRandom.uuid,
      job_class: "ExampleJob",
      queue_name: queue_name,
      scheduled_at: scheduled_at,
      serialized_params: {}
    )
  end
end
