# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoodJob::ApplicationHelper, type: :helper do
  describe "#format_performance_bucket_size" do
    it "uses exact short units and readable approximations for fixed month and year scales" do
      I18n.with_locale(:en) do
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

  describe "#truncate_display_value" do
    it "leaves short strings unchanged" do
      expect(helper.truncate_display_value("short")).to eq("short")
    end

    it "truncates long strings and notes the original length" do
      result = helper.truncate_display_value("a" * 2_000, limit: 10)

      expect(result).to eq("#{'a' * 10}… [2000 characters total]")
    end

    it "truncates strings nested in arrays and hashes" do
      value = { "key" => ["a" * 2_000, { "nested" => "ok" }] }
      result = helper.truncate_display_value(value, limit: 10)

      expect(result).to eq({ "key" => ["#{'a' * 10}… [2000 characters total]", { "nested" => "ok" }] })
    end

    it "passes through other values" do
      expect(helper.truncate_display_value(42)).to eq(42)
      expect(helper.truncate_display_value(nil)).to be_nil
    end
  end
end
