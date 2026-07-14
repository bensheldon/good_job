# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoodJob::PerformanceController, type: :controller do
  render_views # seems required for Rails HEAD

  before do
    @routes = GoodJob::Engine.routes
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
    ExampleJob.perform_later
    GoodJob.perform_inline
  end

  describe '#index' do
    it 'renders the index page' do
      get :index
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Performance')
    end

    it "filters the chart and both tables with the same half-open range" do
      start_time = Time.zone.parse("2024-01-01 10:03:17 UTC")
      end_time = Time.zone.parse("2024-01-01 11:07:42 UTC")

      create_execution(job_class: "BeforeStart", queue_name: "before-start", scheduled_at: start_time - 1.second)
      create_execution(job_class: "AtStart", queue_name: "at-start", scheduled_at: start_time)
      create_execution(job_class: "BeforeEnd", queue_name: "before-end", scheduled_at: end_time - 1.second)
      create_execution(job_class: "AtEnd", queue_name: "at-end", scheduled_at: end_time)

      get :index, params: { chart_start: start_time.iso8601, chart_end: end_time.iso8601 }

      performances = controller.instance_variable_get(:@performances)
      queue_performances = controller.instance_variable_get(:@queue_performances)
      chart_data = controller.instance_variable_get(:@chart_data)

      expect(response).to have_http_status(:ok)
      expect(performances.map(&:job_class)).to contain_exactly("AtStart", "BeforeEnd")
      expect(queue_performances.map(&:queue_name)).to contain_exactly("at-start", "before-end")
      expect(chart_data.dig(:data, :datasets).pluck(:label)).to contain_exactly("AtStart", "BeforeEnd")
    end

    it "renders explicit empty states when the selected range has no executions" do
      get :index, params: {
        chart_start: "2020-01-01T10:03:17Z",
        chart_end: "2020-01-01T11:07:42Z",
      }

      expect(response).to have_http_status(:ok)
      expect(response.body.scan("No executions in this time range.").count).to eq(2)
    end

    it "redirects unsafe range shapes and values once to a rendered default state" do
      invalid_parameters = [
        { chart_start: ["2024-01-01T10:00:00Z"], chart_end: "2024-01-01T11:00:00Z" },
        { chart_start: { value: "2024-01-01T10:00:00Z" }, chart_end: "2024-01-01T11:00:00Z" },
        { chart_start: "NaN", chart_end: "Infinity" },
        { chart_start: "2024-01-01 10:00:00 UTC", chart_end: "2024-01-01T11:00:00Z" },
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
        get :index, params: parameters

        expect(response).to have_http_status(:redirect)
        expect(URI.parse(response.location).query).to be_nil

        get :index

        expect(response).to have_http_status(:ok)
      end
    end

    it "redirects over-maximum custom input to its clamped canonical bounds" do
      get :index, params: {
        chart_start: "2023-01-01T00:00:00Z",
        chart_end: "2024-01-01T00:00:00Z",
      }

      query = Rack::Utils.parse_query(URI.parse(response.location).query)

      expect(response).to have_http_status(:redirect)
      expect(query).to eq(
        "chart_start" => "2023-12-01T00:00:00Z",
        "chart_end" => "2024-01-01T00:00:00Z"
      )
    end

    it "canonicalizes inconsistent or malformed anchored presets without trusting a false identity" do
      get :index, params: {
        chart_range: "1h",
        chart_start: "2024-01-01T10:03:17Z",
        chart_end: "2024-01-01T12:03:17Z",
      }

      expect(response).to have_http_status(:redirect)
      expect(Rack::Utils.parse_query(URI.parse(response.location).query)).to eq(
        "chart_start" => "2024-01-01T10:03:17Z",
        "chart_end" => "2024-01-01T12:03:17Z"
      )

      get :index, params: {
        chart_range: "1h",
        chart_start: "not-a-time",
        chart_end: "2024-01-01T12:03:17Z",
      }

      expect(response).to have_http_status(:redirect)
      expect(Rack::Utils.parse_query(URI.parse(response.location).query)).to eq("chart_range" => "1h")
    end

    it "clamps fall-DST input to 31 elapsed days and renders its canonical range" do
      Time.use_zone("America/New_York") do
        get :index, params: {
          chart_start: "2024-09-01T00:00:00-04:00",
          chart_end: "2024-11-04T00:00:00-05:00",
        }

        query = Rack::Utils.parse_query(URI.parse(response.location).query)

        expect(response).to have_http_status(:redirect)
        expect(query).to eq(
          "chart_start" => "2024-10-04T01:00:00-04:00",
          "chart_end" => "2024-11-04T00:00:00-05:00"
        )

        get :index, params: query

        range = controller.instance_variable_get(:@performance_range)
        expect(response).to have_http_status(:ok)
        expect(range.end_time - range.start_time).to eq((24.hours * 31).to_i)
        expect(range.interval_seconds).to eq(6.hours.to_i)
      end
    end
  end

  describe '#show' do
    it 'renders the show page' do
      get :show, params: { id: "ExampleJob" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Performance - ExampleJob')
    end

    it "raises a 404 when the job doesn't exist" do
      expect do
        get :show, params: { id: "Missing" }
      end.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "renders the page-level range and applies it to the histogram" do
      execution = GoodJob::Execution.find_by!(job_class: "ExampleJob")
      execution.update!(scheduled_at: Time.zone.parse("2024-01-01 10:30:00 UTC"))

      get :show, params: {
        id: "ExampleJob",
        chart_start: "2024-01-01T10:03:17Z",
        chart_end: "2024-01-01T11:07:42Z",
      }

      chart_data = controller.instance_variable_get(:@chart_data)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Performance time range")
      expect(chart_data.dig(:data, :datasets, 0, :data).sum).to eq(1)
    end

    it "uses exact anchored preset bounds without recomputing while retaining the active key" do
      execution = GoodJob::Execution.find_by!(job_class: "ExampleJob")
      execution.update!(scheduled_at: Time.zone.parse("2024-01-01 10:30:00 UTC"))
      create_execution(
        job_class: "ExampleJob",
        queue_name: "default",
        scheduled_at: Time.zone.parse("2024-01-01 11:03:17 UTC")
      )

      get :show, params: {
        id: "ExampleJob",
        chart_range: "1h",
        chart_start: "2024-01-01T10:03:17Z",
        chart_end: "2024-01-01T11:03:17Z",
      }

      range = controller.instance_variable_get(:@performance_range)
      chart_data = controller.instance_variable_get(:@chart_data)

      expect(response).to have_http_status(:ok)
      expect(range.key).to eq("1h")
      expect(range.start_time).to eq(Time.zone.parse("2024-01-01 10:03:17 UTC"))
      expect(range.end_time).to eq(Time.zone.parse("2024-01-01 11:03:17 UTC"))
      expect(chart_data.dig(:data, :datasets, 0, :data).sum).to eq(1)
      expect(Capybara.string(response.body)).to have_css(".performance-range-key", text: "1h")
    end
  end

  def create_execution(job_class:, queue_name:, scheduled_at:)
    GoodJob::Execution.create!(
      active_job_id: SecureRandom.uuid,
      created_at: scheduled_at,
      duration: 1.second,
      job_class: job_class,
      queue_name: queue_name,
      scheduled_at: scheduled_at,
      serialized_params: {},
      updated_at: scheduled_at
    )
  end
end
