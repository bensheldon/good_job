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

    it "canonicalizes native local values in the page timezone and then renders" do
      Time.use_zone("America/St_Johns") do
        get :index, params: {
          chart_start: "2024-01-01T10:03:17",
          chart_end: "2024-01-01T11:07:42",
        }

        query = Rack::Utils.parse_query(URI.parse(response.location).query)

        expect(response).to have_http_status(:redirect)
        expect(query).to eq(
          "chart_start" => "2024-01-01T10:03:17-03:30",
          "chart_end" => "2024-01-01T11:07:42-03:30"
        )

        get :index, params: query

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("America/St_Johns")
        start_input = Capybara.string(response.body).find("input[name='chart_start']")
        expect(start_input["aria-label"]).to eq("Start time")
        expect(start_input["value"]).to eq("2024-01-01T10:03:17")
      end
    end

    it "renders the application-zone range form before JavaScript enhancement" do
      Time.use_zone("America/St_Johns") do
        get :index, params: {
          chart_start: "2024-01-01T06:33:17-03:30",
          chart_end: "2024-01-01T07:37:42-03:30",
        }

        page = Capybara.string(response.body)
        form = page.find("form[data-controller='performance-range']")
        start_input = page.find("input[type='datetime-local'][name='chart_start']")
        end_input = page.find("input[type='datetime-local'][name='chart_end']")
        start_canonical = page.find("input[type='hidden'][name='chart_start'][disabled]", visible: :all)
        end_canonical = page.find("input[type='hidden'][name='chart_end'][disabled]", visible: :all)
        time_zone_input = page.find("input[type='hidden'][name='chart_time_zone'][disabled]", visible: :all)

        expect(response).to have_http_status(:ok)
        expect(form["data-action"]).to eq("submit->performance-range#prepareSubmission")
        expect(start_input["value"]).to eq("2024-01-01T06:33:17")
        expect(end_input["value"]).to eq("2024-01-01T07:37:42")
        expect(start_canonical["value"]).to eq("2024-01-01T06:33:17-03:30")
        expect(end_canonical["value"]).to eq("2024-01-01T07:37:42-03:30")
        expect(time_zone_input["value"]).to be_blank
        expect(page).to have_css("#performance-range-time-zone > span:first-child", text: "Time zone:")
        expect(page).to have_css("[data-performance-range-target='timeZoneLabel']", text: "America/St_Johns")
        expect(page).to have_link("Last 1 hour", href: performance_index_path(chart_range: "1h", locale: nil))
        expect(page.find("a.performance-range-reload")[:href]).to eq(
          performance_index_path(
            chart_start: "2024-01-01T06:33:17-03:30",
            chart_end: "2024-01-01T07:37:42-03:30",
            locale: nil
          )
        )
        expect(page.find("a.performance-range-reload")["data-turbo"]).to eq("false")
        expect(page).to have_no_css("a.performance-range-reload.disabled")
      end
    end

    it "canonicalizes browser-local edits and removes the transient timezone" do
      Time.use_zone("UTC") do
        get :index, params: {
          chart_start: "2024-01-01T10:03:17",
          chart_end: "2024-01-01T11:07:42",
          chart_time_zone: "America/St_Johns",
        }

        query = Rack::Utils.parse_query(URI.parse(response.location).query)

        expect(response).to have_http_status(:redirect)
        expect(query).to eq(
          "chart_start" => "2024-01-01T13:33:17Z",
          "chart_end" => "2024-01-01T14:37:42Z"
        )
      end
    end

    it "rejects nonexistent local endpoint times without redirecting twice" do
      Time.use_zone("America/New_York") do
        [
          { chart_start: "2024-03-10T02:30:00", chart_end: "2024-03-10T04:00:00" },
          { chart_start: "2024-03-10T01:00:00", chart_end: "2024-03-10T02:30:00" },
        ].each do |parameters|
          get :index, params: parameters

          expect(response).to have_http_status(:redirect)
          expect(URI.parse(response.location).query).to be_nil

          get :index
          expect(response).to have_http_status(:ok)
        end
      end
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

    it "renders custom input longer than 31 days without truncating its bounds" do
      get :index, params: {
        chart_start: "2023-01-01T00:00:00Z",
        chart_end: "2024-01-01T00:00:00Z",
      }

      range = controller.instance_variable_get(:@performance_range)

      expect(response).to have_http_status(:ok)
      expect(range.to_params).to eq(
        "chart_start" => "2023-01-01T00:00:00Z",
        "chart_end" => "2024-01-01T00:00:00Z"
      )
      expect(range.interval_seconds).to eq(14.days.to_i)
      expect(Capybara.string(response.body)).to have_css(
        ".performance-chart-bucket-size",
        text: "Chart bucket size: 14d"
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

    it "renders a long fall-DST range without truncating elapsed time" do
      Time.use_zone("America/New_York") do
        get :index, params: {
          chart_start: "2024-09-01T00:00:00-04:00",
          chart_end: "2024-11-04T00:00:00-05:00",
        }

        range = controller.instance_variable_get(:@performance_range)

        expect(response).to have_http_status(:ok)
        expect(range.start_time.iso8601).to eq("2024-09-01T00:00:00-04:00")
        expect(range.end_time.iso8601).to eq("2024-11-04T00:00:00-05:00")
        expect(range.end_time - range.start_time).to eq((64.days + 1.hour).to_i)
        expect(range.interval_seconds).to eq(3.days.to_i)
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
      expect(Capybara.string(response.body)).to have_no_css(".performance-chart-bucket-size")
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
