# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoodJob::ApplicationHelper, type: :helper do
  describe "#format_performance_bucket_size" do
    it "uses exact short units and readable approximations for fixed month and year scales" do
      expect(helper.format_performance_bucket_size(2.seconds.to_i)).to eq("2s")
      expect(helper.format_performance_bucket_size(5.minutes.to_i)).to eq("5m")
      expect(helper.format_performance_bucket_size(1.hour.to_i)).to eq("1h")
      expect(helper.format_performance_bucket_size(14.days.to_i)).to eq("14d")
      expect(helper.format_performance_bucket_size(30.days.to_i)).to eq("~1mo")
      expect(helper.format_performance_bucket_size(180.days.to_i)).to eq("~6mo")
      expect(helper.format_performance_bucket_size(365.days.to_i)).to eq("~1y")
      expect(helper.format_performance_bucket_size(2 * 365.days.to_i)).to eq("~2y")
    end
  end
end
