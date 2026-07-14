# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoodJob::ApplicationHelper, type: :helper do
  describe "#format_performance_bucket_size" do
    it "uses the largest exact elapsed unit while keeping long buckets in days" do
      expect(helper.format_performance_bucket_size(2.seconds.to_i)).to eq("2s")
      expect(helper.format_performance_bucket_size(5.minutes.to_i)).to eq("5m")
      expect(helper.format_performance_bucket_size(1.hour.to_i)).to eq("1h")
      expect(helper.format_performance_bucket_size(30.days.to_i)).to eq("30d")
      expect(helper.format_performance_bucket_size(365.days.to_i)).to eq("365d")
    end
  end
end
