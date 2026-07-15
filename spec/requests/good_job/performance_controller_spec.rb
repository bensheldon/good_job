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
        range_path: good_job.performance_index_path(locale: nil),
        preset_path: good_job.performance_index_path(chart_range: "6h", locale: "de"),
        reload_path: good_job.performance_index_path(chart_range: "1h", locale: "de")
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
        range_path: good_job.performance_path("ExampleJob", locale: nil),
        preset_path: good_job.performance_path("ExampleJob", chart_range: "6h", locale: "de"),
        reload_path: good_job.performance_path("ExampleJob", chart_range: "1h", locale: "de")
      )
    end

    it "links presets to the same exact custom range on index and show" do
      anchored_range = {
        chart_range: "1h",
        chart_start: "2024-01-01T10:03:17-03:30",
        chart_end: "2024-01-01T11:03:17-03:30",
        locale: "de",
      }
      custom_range = anchored_range.except(:chart_range)

      Time.use_zone("America/St_Johns") do
        [
          good_job.performance_index_path,
          good_job.performance_path("ExampleJob"),
        ].each do |path|
          get path, params: anchored_range

          expect(response).to have_http_status(:ok)
          custom_link = Capybara.string(response.body).find("a.performance-range-custom")
          expect(custom_link[:href]).to eq("#{path}?#{custom_range.to_query}")
        end
      end
    end

    it "reloads an exact custom range without changing its bounds" do
      custom_range = {
        chart_start: "2024-01-01T10:03:17Z",
        chart_end: "2024-01-01T11:07:42Z",
      }

      get good_job.performance_index_path, params: custom_range.merge(locale: "de")

      expect(response).to have_http_status(:ok)
      reload_link = Capybara.string(response.body).find("a.performance-range-reload")
      expect(reload_link[:href]).to eq(good_job.performance_index_path(**custom_range, locale: "de"))
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

    it "redirects reserved URL input to exact trusted index and show destinations" do
      [
        good_job.performance_index_path,
        good_job.performance_path("ExampleJob"),
      ].each do |path|
        hostile_query = reserved_url_options.merge(chart_start: "not-a-time").to_query
        get "#{path}?#{hostile_query}"

        redirect_uri = URI.parse(response.location)

        expect(response).to have_http_status(:redirect)
        expect(response.location).to eq("http://www.example.com#{path}?locale=de")
        expect(redirect_uri.scheme).to eq("http")
        expect(redirect_uri.host).to eq("www.example.com")
        expect(redirect_uri.port).to eq(80)
        expect(redirect_uri.path).to eq(path)
        expect(Rack::Utils.parse_query(redirect_uri.query)).to eq("locale" => "de")
        expect(redirect_uri.fragment).to be_nil
      end
    end
  end

  def expect_range_links(range_path:, preset_path:, reload_path:)
    page = Capybara.string(response.body)
    preset_paths = page.all("a.performance-range-menu-item").map { |link| link[:href] }
    custom_uri = URI.parse(page.find("a.performance-range-custom")[:href])
    custom_query = Rack::Utils.parse_query(custom_uri.query)

    expect(preset_paths).to include(preset_path)
    expect(page.find("a.performance-range-reload")[:href]).to eq(reload_path)
    expect(custom_uri.path).to eq(range_path)
    expect(custom_query.keys).to contain_exactly("chart_start", "chart_end", "locale")
    expect(custom_query.fetch("locale")).to eq("de")
    expect(Time.iso8601(custom_query.fetch("chart_end")) - Time.iso8601(custom_query.fetch("chart_start"))).to eq(1.hour)
  end
end
