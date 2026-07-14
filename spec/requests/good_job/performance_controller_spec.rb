# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoodJob::PerformanceController do
  let(:reserved_url_options) do
    {
      action: "show",
      anchor: "hostile-fragment",
      controller: "good_job/jobs",
      host: "attacker.example",
      id: "hostile-id",
      locale: "de",
      only_path: "false",
      port: "8443",
      protocol: "https",
    }
  end

  before do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
    ExampleJob.perform_later
    GoodJob.perform_inline
  end

  describe "range navigation" do
    it "uses fixed index paths and only allowlisted range and locale keys with reserved query input" do
      get good_job.performance_index_path, params: reserved_url_options.merge(chart_range: "1h")

      expect(response).to have_http_status(:ok)
      expect_range_links(
        preset_path: good_job.performance_index_path(chart_range: "6h", locale: "de"),
        reset_path: good_job.performance_index_path(locale: "de")
      )

      drilldown_uri = URI.parse(Capybara.string(response.body).find(".performance-name a")[:href])
      drilldown_query = Rack::Utils.parse_query(drilldown_uri.query)

      expect(drilldown_uri.path).to eq(good_job.performance_path("ExampleJob", locale: nil))
      expect(drilldown_query.keys).to contain_exactly("chart_range", "chart_start", "chart_end", "locale")
      expect(drilldown_query.fetch("chart_range")).to eq("1h")
      expect(drilldown_query.fetch("locale")).to eq("de")
      expect(Time.iso8601(drilldown_query.fetch("chart_end")) - Time.iso8601(drilldown_query.fetch("chart_start"))).to eq(1.hour)
    end

    it "uses fixed show paths and only allowlisted range and locale keys with reserved query input" do
      get good_job.performance_path("ExampleJob"), params: reserved_url_options.merge(chart_range: "1h")

      expect(response).to have_http_status(:ok)
      expect_range_links(
        preset_path: good_job.performance_path("ExampleJob", chart_range: "6h", locale: "de"),
        reset_path: good_job.performance_path("ExampleJob", locale: "de")
      )
    end
  end

  describe "unsafe timestamp input" do
    it "canonicalizes repeated scalar parameters once and renders without a query exception" do
      query_string = URI.encode_www_form([
                                           ["chart_start", "2024-01-01T10:00:00Z"],
                                           ["chart_start", "2024-01-01T10:30:00Z"],
                                           ["chart_end", "2024-01-01T11:00:00Z"],
                                         ])

      get "#{good_job.performance_index_path}?#{query_string}"

      expect(response).to redirect_to(good_job.performance_index_path(locale: nil))

      follow_redirect!

      expect(response).to have_http_status(:ok)
    end

    it "strips transient timezone state without changing exact endpoints" do
      get good_job.performance_index_path, params: {
        chart_start: "2024-01-01T10:03:17Z",
        chart_end: "2024-01-01T11:07:42Z",
        chart_time_zone: "Missing/Zone",
      }

      redirect_uri = URI.parse(response.location)

      expect(response).to have_http_status(:redirect)
      expect(redirect_uri.path).to eq(good_job.performance_index_path(locale: nil))
      expect(Rack::Utils.parse_query(redirect_uri.query)).to eq(
        "chart_start" => "2024-01-01T10:03:17Z",
        "chart_end" => "2024-01-01T11:07:42Z"
      )
    end
  end

  def expect_range_links(preset_path:, reset_path:)
    page = Capybara.string(response.body)
    preset_paths = page.all("a.performance-range-menu-item").map { |link| link[:href] }

    expect(preset_paths).to include(preset_path)
    expect(page.find(".performance-range-control > a")[:href]).to eq(reset_path)
  end
end
