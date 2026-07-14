# frozen_string_literal: true

require 'rails_helper'

describe 'Performance Page', :js do
  before do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
  end

  after do
    # Drain Puma before the shared cleaner disconnects; Rails can otherwise leave
    # an idle server thread owning a connection between these browser examples.
    Capybara.reset_sessions!
    ApplicationRecord.connection_pool.disconnect!
  end

  it 'renders index properly' do
    ExampleJob.perform_later
    GoodJob.perform_inline

    visit good_job.root_path
    click_link 'Performance'
    expect(page).to have_css 'h2', text: 'Performance'
    expect(page).to have_content 'ExampleJob'
  end

  it 'can select and reset a chart range on the index' do
    ExampleJob.perform_later
    GoodJob.perform_inline

    visit good_job.performance_index_path

    click_button "Open performance time ranges"
    click_link "Last 1 hour"

    expect(page).to have_current_path(/chart_range=1h/)
    expect(page).to have_css(".performance-range-key", text: "1h")

    find("a[aria-label='Reset performance time range']").click

    expect(page).to have_no_current_path(/chart_range=/)
    expect(page).to have_css(".performance-range-key", text: "24h")
    expect(page).to have_css("a[aria-label='Reset performance time range'].disabled")
  end

  it "presents the range state with accessible contrast, keyboard focus, and compact narrow layout" do
    with_narrow_viewport do
      visit good_job.performance_index_path

      expect(page).to have_css("span.performance-range-state", count: 3)
      expect(page).to have_no_css(".performance-range-state.disabled")
      expect(page).to have_no_css("a.performance-range-state, button.performance-range-state")

      state_styles = page.evaluate_script(<<~JAVASCRIPT)
        Array.from(document.querySelectorAll(".performance-range-state")).map((element) => {
          const style = getComputedStyle(element)
          return {
            backgroundColor: style.backgroundColor,
            color: style.color,
            opacity: style.opacity,
          }
        })
      JAVASCRIPT

      state_styles.each do |style|
        expect(style.fetch("opacity")).to eq("1")
        expect(contrast_ratio(style.fetch("color"), style.fetch("backgroundColor"))).to be >= 4.5
      end

      12.times do
        break if page.evaluate_script("document.activeElement.classList.contains('performance-range-toggle')")

        page.driver.browser.keyboard.type(:tab)
      end

      focus_style = page.evaluate_script(<<~JAVASCRIPT)
        (() => {
          const style = getComputedStyle(document.activeElement)
          return {
            className: document.activeElement.className,
            outlineStyle: style.outlineStyle,
            outlineWidth: style.outlineWidth,
          }
        })()
      JAVASCRIPT

      expect(focus_style.fetch("className")).to include("performance-range-toggle")
      expect(focus_style.fetch("outlineStyle")).to eq("solid")
      expect(focus_style.fetch("outlineWidth").to_f).to be >= 3

      geometry = page.evaluate_script(<<~JAVASCRIPT)
        (() => {
          const toggle = document.querySelector(".performance-range-toggle").getBoundingClientRect()
          const reset = document.querySelector(".performance-range-reset").getBoundingClientRect()
          return {
            resetTop: reset.top,
            resetWidth: reset.width,
            toggleTop: toggle.top,
          }
        })()
      JAVASCRIPT

      expect(geometry.fetch("resetTop")).to be_within(1).of(geometry.fetch("toggleTop"))
      expect(geometry.fetch("resetWidth")).to be < 50
    end
  end

  it 'can select a custom page range by dragging the index chart' do
    Timecop.freeze(Time.zone.parse("2024-01-01 12:34:56 UTC")) do
      ExampleJob.perform_later
      GoodJob.perform_inline

      visit good_job.performance_index_path(chart_range: "1h")

      chart_config = JSON.parse(find("[data-chart-config-value]")["data-chart-config-value"])
      chart_metadata = chart_config.fetch("goodJob")
      timestamps = chart_metadata.fetch("timestamps")
      interval_seconds = chart_metadata.fetch("interval_seconds")
      range_start = Time.iso8601(chart_metadata.fetch("range_start"))
      range_end = Time.iso8601(chart_metadata.fetch("range_end"))
      chart_area = page.evaluate_script("Chart.getChart(document.querySelector('[data-chart-target=\"canvas\"]')).chartArea")
      canvas_rect = page.evaluate_script("document.querySelector('[data-chart-target=\"canvas\"]').getBoundingClientRect().toJSON()")
      y = canvas_rect.fetch("y") + ((chart_area.fetch("top") + chart_area.fetch("bottom")) / 2)
      start_x = canvas_rect.fetch("x") + chart_area.fetch("left") + 1
      end_x = canvas_rect.fetch("x") + chart_area.fetch("right") - 1

      expect(Time.iso8601(timestamps.first)).to be < range_start
      expect(Time.iso8601(timestamps.last) + interval_seconds).to be > range_end

      page.driver.browser.mouse.move(x: start_x, y: y)
      page.driver.browser.mouse.down
      page.driver.browser.mouse.move(x: end_x, y: y, steps: 5)
      page.driver.browser.mouse.up

      expect(page).to have_current_path(/chart_start=/)
      expect(page).to have_current_path(/chart_end=/)
      expect(page).to have_no_current_path(/chart_range=/)
      expect(page).to have_css(".performance-range-key", text: "Custom")

      query = Rack::Utils.parse_query(URI.parse(page.current_url).query)
      expect(Time.iso8601(query.fetch("chart_start"))).to eq(range_start)
      expect(Time.iso8601(query.fetch("chart_end"))).to eq(range_end)
    end
  end

  it "shows explicit empty table states for a range without executions" do
    visit good_job.performance_index_path(
      chart_start: "2020-01-01T10:03:17Z",
      chart_end: "2020-01-01T11:07:42Z"
    )

    expect(page).to have_content("No executions in this time range.", count: 2)
  end

  it 'preserves exact preset bounds and identity on show until reset establishes a fresh window' do
    initial_time = Time.zone.parse("2024-01-01 12:34:56.500 UTC")

    Timecop.freeze(initial_time) do
      ExampleJob.perform_later
      GoodJob.perform_inline
      GoodJob::Execution.find_by!(job_class: "ExampleJob").update!(scheduled_at: initial_time - 30.minutes)

      ExampleJob.perform_later
      GoodJob.perform_inline
      GoodJob::Execution.where(job_class: "ExampleJob").order(:created_at).last!
                        .update!(scheduled_at: initial_time + 5.seconds)

      visit good_job.performance_index_path

      index_dates = all(".performance-range-date").map(&:text)
      index_config = JSON.parse(find("[data-chart-config-value]")["data-chart-config-value"])
      expected_navigation = {
        "chart_range" => "24h",
        "chart_start" => index_config.dig("goodJob", "range_start"),
        "chart_end" => index_config.dig("goodJob", "range_end"),
      }
      drilldown_query = Rack::Utils.parse_query(URI.parse(find(".performance-name a")[:href]).query)

      expect(drilldown_query).to eq(expected_navigation)

      Timecop.travel(initial_time + 12.seconds)
      click_link 'ExampleJob'

      show_query = Rack::Utils.parse_query(URI.parse(page.current_url).query)
      show_config = JSON.parse(find("[data-chart-config-value]")["data-chart-config-value"])

      expect(page).to have_css 'h2', text: 'Performance - ExampleJob'
      expect(show_query).to eq(expected_navigation)
      expect(all(".performance-range-date").map(&:text)).to eq(index_dates)
      expect(page).to have_css(".performance-range-key", text: "24h")
      expect(show_config.dig("data", "datasets", 0, "data").sum).to eq(1)

      find("a[aria-label='Reset performance time range']").click

      expect(page).to have_no_current_path(/chart_(?:range|start|end)=/)
      expect(page).to have_css(".performance-range-key", text: "24h")
      expect(all(".performance-range-date").map(&:text)).not_to eq(index_dates)
    end
  end

  def contrast_ratio(foreground, background)
    luminances = [foreground, background].map do |color|
      channels = color.scan(/\d+(?:\.\d+)?/).first(3).map do |channel|
        value = channel.to_f / 255
        value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
      end
      (0.2126 * channels[0]) + (0.7152 * channels[1]) + (0.0722 * channels[2])
    end

    (luminances.max + 0.05) / (luminances.min + 0.05)
  end

  def with_narrow_viewport
    page.current_window.resize_to(390, 844)
    yield
  ensure
    page.current_window.resize_to(1024, 800)
  end
end
