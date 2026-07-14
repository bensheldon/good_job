# frozen_string_literal: true

require 'rails_helper'

describe 'Performance Page', :js do
  before do
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :external)
    page.driver.browser.page.command("Emulation.setTimezoneOverride", timezoneId: "UTC")
  end

  after do
    # Preserve Capybara's server-error check, then close Cuprite and drain again so
    # browser cleanup cannot race the shared database cleaner with a late request.
    Capybara.reset_sessions!
  ensure
    Capybara.current_session.quit
    Capybara.reset_sessions!
    ApplicationRecord.connection_pool.disconnect
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

  it "presents standard-size range controls with accessible, start-aligned narrow wrapping" do
    with_narrow_viewport do
      visit good_job.performance_index_path

      expect(page).to have_css(".performance-range-state", count: 3)
      expect(page).to have_no_css(".performance-range-state.disabled")
      expect(page).to have_no_css("a.performance-range-state, button.performance-range-state")
      expect(page).to have_css("#performance-range-name", text: "Performance time range", visible: :all)
      browser_time_zone = page.evaluate_script("new Intl.DateTimeFormat().resolvedOptions().timeZone")
      expect(page).to have_css("[data-performance-range-target='timeZoneLabel']", text: browser_time_zone)

      field_contract = page.evaluate_script(<<~JAVASCRIPT)
        (() => {
          const start = document.querySelector("[data-performance-range-target='startInput']")
          const end = document.querySelector("[data-performance-range-target='endInput']")
          return {
            endMaximum: end.max,
            endMinimumOffset: Date.parse(`${end.min}Z`) - start.valueAsNumber,
            endStep: end.step,
            startMaximumOffset: end.valueAsNumber - Date.parse(`${start.max}Z`),
            startMinimum: start.min,
            startStep: start.step,
          }
        })()
      JAVASCRIPT

      expect(field_contract).to eq(
        "endMaximum" => "9999-12-31T23:59:59",
        "endMinimumOffset" => 1_000,
        "endStep" => "1",
        "startMaximumOffset" => 1_000,
        "startMinimum" => "1000-01-01T00:00:00",
        "startStep" => "1"
      )

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

      focus_style = page.evaluate_script(<<~JAVASCRIPT)
        (() => {
          const input = document.querySelector("[data-performance-range-target='startInput']")
          input.focus()
          const style = getComputedStyle(input.closest(".performance-range-date"))
          return {
            outlineStyle: style.outlineStyle,
            outlineWidth: style.outlineWidth,
          }
        })()
      JAVASCRIPT

      expect(focus_style.fetch("outlineStyle")).to eq("solid")
      expect(focus_style.fetch("outlineWidth").to_f).to be >= 3

      focus_sequence = []
      30.times do
        current_focus = page.evaluate_script(<<~JAVASCRIPT)
          document.activeElement.getAttribute("aria-label") || document.activeElement.value
        JAVASCRIPT
        focus_sequence << current_focus unless focus_sequence.last == current_focus
        break if current_focus == "Open performance time ranges"

        page.driver.browser.keyboard.type(:tab)
      end
      expect(focus_sequence).to eq(
        [
          "Start time",
          "End time",
          "Open performance time ranges",
        ]
      )

      page.execute_script(<<~JAVASCRIPT)
        document.querySelector("[data-performance-range-target='startInput']").showPicker = function() {
          document.body.dataset.performancePicker = this.id
        }
      JAVASCRIPT
      first(".performance-range-date").click
      expect(page.evaluate_script("document.body.dataset.performancePicker")).to eq("chart_start")

      geometry = page.evaluate_script(<<~JAVASCRIPT)
        (() => {
          const control = document.querySelector(".performance-range-control")
          const controlBounds = control.getBoundingClientRect()
          const items = Array.from(control.children).map((element) => {
            const bounds = element.getBoundingClientRect()
            const style = getComputedStyle(element)
            return {
              fontSize: style.fontSize,
              height: bounds.height,
              left: bounds.left,
              right: bounds.right,
              top: bounds.top,
            }
          })
          return {
            controlLeft: controlBounds.left,
            items,
            scrollWidth: document.documentElement.scrollWidth,
            viewportWidth: window.innerWidth,
          }
        })()
      JAVASCRIPT

      expect(geometry.fetch("scrollWidth")).to be <= geometry.fetch("viewportWidth")
      geometry.fetch("items").each do |item|
        expect(item.fetch("fontSize")).to eq("16px")
        expect(item.fetch("height")).to be >= 38
        expect(item.fetch("right")).to be <= geometry.fetch("viewportWidth")
      end
      expect(geometry.dig("items", 0, "left")).to be_within(1).of(geometry.fetch("controlLeft"))
      geometry.fetch("items").each_cons(2) do |previous, current|
        ordered = current.fetch("top") > previous.fetch("top") ||
                  current.fetch("left") >= previous.fetch("left")
        expect(ordered).to be(true)
      end

      click_button "Open performance time ranges"
      hint_layout = page.evaluate_script(<<~JAVASCRIPT)
        (() => {
          const hint = document.querySelector(".performance-range-menu small")
          const style = getComputedStyle(hint)
          return {
            height: hint.getBoundingClientRect().height,
            lineHeight: Number.parseFloat(style.lineHeight),
            whiteSpace: style.whiteSpace,
          }
        })()
      JAVASCRIPT

      expect(hint_layout.fetch("whiteSpace")).to eq("nowrap")
      expect(hint_layout.fetch("height")).to be_within(1).of(hint_layout.fetch("lineHeight"))
    end
  end

  it "updates native local ranges on both performance pages and prevents crossed endpoints" do
    Timecop.freeze(Time.zone.parse("2024-01-01 12:34:56 UTC")) do
      ExampleJob.perform_later
      GoodJob.perform_inline

      [
        good_job.performance_index_path(chart_range: "1h"),
        good_job.performance_path("ExampleJob", chart_range: "1h"),
      ].each do |path|
        visit path

        page.execute_script(<<~JAVASCRIPT)
          const start = document.querySelector("[data-performance-range-target='startInput']")
          const end = document.querySelector("[data-performance-range-target='endInput']")
          start.value = "2024-01-01T10:03:17"
          end.value = "2024-01-01T11:07:42"
          start.dispatchEvent(new Event("input", { bubbles: true }))
          end.dispatchEvent(new Event("input", { bubbles: true }))
        JAVASCRIPT

        constraints = page.evaluate_script(<<~JAVASCRIPT)
          (() => {
            const start = document.querySelector("[data-performance-range-target='startInput']")
            const end = document.querySelector("[data-performance-range-target='endInput']")
            start.value = end.value
            start.dispatchEvent(new Event("input", { bubbles: true }))
            const crossed = {
              formValid: start.form.checkValidity(),
              rangeOverflow: start.validity.rangeOverflow,
            }
            start.value = "2024-01-01T10:03:17"
            start.dispatchEvent(new Event("input", { bubbles: true }))
            end.dispatchEvent(new Event("change", { bubbles: true }))
            return crossed
          })()
        JAVASCRIPT

        expect(constraints).to eq("formValid" => false, "rangeOverflow" => true)

        expect(page).to have_current_path(/chart_start=/)

        query = Rack::Utils.parse_query(URI.parse(page.current_url).query)
        expect(query.keys).to contain_exactly("chart_start", "chart_end")
        expect(Time.iso8601(query.fetch("chart_start"))).to eq(Time.zone.parse("2024-01-01 10:03:17 UTC"))
        expect(Time.iso8601(query.fetch("chart_end"))).to eq(Time.zone.parse("2024-01-01 11:07:42 UTC"))
        expect(page).to have_css(".performance-range-key", text: "Custom")
      end
    end
  end

  it "keeps the widget and index axis in browser time while retaining exact canonical endpoints" do
    with_browser_time_zone("America/St_Johns") do
      visit good_job.performance_index_path(
        chart_start: "2024-01-01T10:03:17Z",
        chart_end: "2024-01-01T11:07:42Z"
      )

      browser_state = page.evaluate_script(<<~JAVASCRIPT)
        (() => {
          const start = document.querySelector("[data-performance-range-target='startInput']")
          const end = document.querySelector("[data-performance-range-target='endInput']")
          const startCanonical = document.querySelector("[data-performance-range-target='startCanonicalInput']")
          const endCanonical = document.querySelector("[data-performance-range-target='endCanonicalInput']")
          const chartElement = document.querySelector("[data-chart-target='canvas']")
          const chart = Chart.getChart(chartElement)
          const metadata = JSON.parse(document.querySelector("[data-chart-config-value]").dataset.chartConfigValue).goodJob
          const formatter = new Intl.DateTimeFormat(document.documentElement.lang, {
            hour: "2-digit",
            hourCycle: "h23",
            minute: "2-digit",
          })

          return {
            actualChartLabel: chart.data.labels[0],
            canonicalValues: [startCanonical.value, endCanonical.value],
            expectedChartLabel: formatter.format(new Date(metadata.timestamps[0])),
            inputNames: [start.name, end.name],
            inputValues: [start.value, end.value],
          }
        })()
      JAVASCRIPT

      expect(page).to have_css("[data-performance-range-target='timeZoneLabel']", text: "America/St_Johns")
      expect(browser_state.fetch("actualChartLabel")).to eq(browser_state.fetch("expectedChartLabel"))
      expect(browser_state.except("actualChartLabel", "expectedChartLabel")).to eq(
        "canonicalValues" => ["2024-01-01T10:03:17Z", "2024-01-01T11:07:42Z"],
        "inputNames" => ["", ""],
        "inputValues" => ["2024-01-01T06:33:17", "2024-01-01T07:37:42"]
      )

      page.execute_script(<<~JAVASCRIPT)
        const url = new URL(window.location.href)
        url.searchParams.set("after_at", "browser-time-navigation-marker")
        window.history.replaceState({}, "", url)

        const end = document.querySelector("[data-performance-range-target='endInput']")
        end.value = "2024-01-01T07:40:00"
        end.dispatchEvent(new Event("input", { bubbles: true }))
        end.dispatchEvent(new Event("change", { bubbles: true }))
      JAVASCRIPT

      expect(page).to have_no_current_path(/after_at=/)
      query = Rack::Utils.parse_query(URI.parse(page.current_url).query)
      expect(query).to eq(
        "chart_start" => "2024-01-01T10:03:17Z",
        "chart_end" => "2024-01-01T11:10:00Z"
      )
    end
  end

  it "localizes sub-minute and multi-year chart labels at their required precision" do
    examples = [
      {
        params: {
          chart_start: "2024-01-01T10:00:01Z",
          chart_end: "2024-01-01T10:00:46Z",
        },
        bucket_size: "2s",
        style: "time_seconds",
      },
      {
        params: {
          chart_start: "2004-07-01T00:00:00Z",
          chart_end: "2024-07-01T00:00:00Z",
        },
        bucket_size: "365d",
        style: "date_time_year",
      },
    ]

    with_browser_time_zone("America/St_Johns") do
      examples.each do |example|
        visit good_job.performance_index_path(example.fetch(:params))

        label_state = page.evaluate_script(<<~JAVASCRIPT)
          (() => {
            const chartElement = document.querySelector("[data-chart-target='canvas']")
            const chart = Chart.getChart(chartElement)
            const metadata = JSON.parse(document.querySelector("[data-chart-config-value]").dataset.chartConfigValue).goodJob
            const options = {
              hour: "2-digit",
              hourCycle: "h23",
              minute: "2-digit",
            }
            if (metadata.timestamp_label_style === "time_seconds") options.second = "2-digit"
            if (["date_time", "date_time_year"].includes(metadata.timestamp_label_style)) {
              options.day = "numeric"
              options.month = "short"
            }
            if (metadata.timestamp_label_style === "date_time_year") options.year = "numeric"

            return {
              actual: chart.data.labels[0],
              coordinateCount: metadata.timestamps.length,
              expected: new Intl.DateTimeFormat(document.documentElement.lang, options).format(new Date(metadata.timestamps[0])),
              labelStyle: metadata.timestamp_label_style,
            }
          })()
        JAVASCRIPT

        expect(label_state.fetch("actual")).to eq(label_state.fetch("expected"))
        expect(label_state.fetch("coordinateCount")).to be <= GoodJob::PerformanceRange::MAXIMUM_TIME_SERIES_COORDINATES
        expect(label_state.fetch("labelStyle")).to eq(example.fetch(:style))
        expect(page).to have_css(
          ".performance-chart-bucket-size",
          text: "Chart bucket size: #{example.fetch(:bucket_size)}"
        )

        next unless example.fetch(:style) == "date_time_year"

        endpoint_labels = all(".performance-range-date").map(&:text)
        expect(endpoint_labels.first).to include("2004")
        expect(endpoint_labels.last).to include("2024")
      end
    end
  end

  it "disambiguates repeated fall-back chart ticks and exact endpoints in browser time" do
    with_time_zone("America/New_York") do
      with_browser_time_zone("America/New_York") do
        visit good_job.performance_index_path(
          chart_start: "2024-11-03T00:45:00-04:00",
          chart_end: "2024-11-03T01:45:00-05:00"
        )

        label_state = page.evaluate_script(<<~JAVASCRIPT)
          (() => {
            const chart = Chart.getChart(document.querySelector("[data-chart-target='canvas']"))
            return {
              chartLabels: chart.data.labels,
              endpointLabels: Array.from(document.querySelectorAll(".performance-range-date"), element => element.innerText.trim()),
            }
          })()
        JAVASCRIPT

        expect(label_state.fetch("chartLabels")).to include("01:00 GMT-4", "01:00 GMT-5")
        expect(label_state.dig("endpointLabels", 0)).to include("GMT-4")
        expect(label_state.dig("endpointLabels", 1)).to include("GMT-5")
      end
    end
  end

  it "prepares browser-local edits submitted directly through the form" do
    with_browser_time_zone("America/St_Johns") do
      visit good_job.performance_index_path(
        chart_start: "2024-01-01T10:03:17Z",
        chart_end: "2024-01-01T11:07:42Z"
      )

      page.execute_script(<<~JAVASCRIPT)
        const url = new URL(window.location.href)
        url.searchParams.set("after_at", "direct-submit-navigation-marker")
        window.history.replaceState({}, "", url)

        const start = document.querySelector("[data-performance-range-target='startInput']")
        start.value = "2024-01-01T06:40:00"
        start.dispatchEvent(new Event("input", { bubbles: true }))
        start.form.requestSubmit()
      JAVASCRIPT

      expect(page).to have_no_current_path(/after_at=/)
      query = Rack::Utils.parse_query(URI.parse(page.current_url).query)
      expect(query).to eq(
        "chart_start" => "2024-01-01T10:10:00Z",
        "chart_end" => "2024-01-01T11:07:42Z"
      )
    end
  end

  it "keeps exact repeated-hour ranges continuous when their local values are not ordered" do
    with_time_zone("America/New_York") do
      with_browser_time_zone("America/New_York") do
        [
          {
            chart_range: "1h",
            chart_start: "2024-11-03T01:30:00-04:00",
            chart_end: "2024-11-03T01:30:00-05:00",
          },
          {
            chart_start: "2024-11-03T01:45:00-04:00",
            chart_end: "2024-11-03T01:15:00-05:00",
          },
        ].each do |parameters|
          visit good_job.performance_index_path(parameters)

          field_state = page.evaluate_script(<<~JAVASCRIPT)
            (() => {
              const start = document.querySelector("[data-performance-range-target='startInput']")
              const end = document.querySelector("[data-performance-range-target='endInput']")
              return {
                endMinimum: end.min,
                formValid: start.form.checkValidity(),
                startMaximum: start.max,
                values: [start.value, end.value],
              }
            })()
          JAVASCRIPT
          chart_metadata = JSON.parse(find("[data-chart-config-value]")["data-chart-config-value"]).fetch("goodJob")

          expect(field_state.fetch("formValid")).to be(true)
          expect(field_state.fetch("startMaximum")).to eq("9999-12-31T23:59:59")
          expect(field_state.fetch("endMinimum")).to eq("1000-01-01T00:00:00")
          expect(chart_metadata.fetch("range_start")).to eq(parameters.fetch(:chart_start))
          expect(chart_metadata.fetch("range_end")).to eq(parameters.fetch(:chart_end))
        end

        page.execute_script(<<~JAVASCRIPT)
          const url = new URL(window.location.href)
          url.searchParams.set("after_at", "fold-edit-marker")
          window.history.replaceState({}, "", url)

          const end = document.querySelector("[data-performance-range-target='endInput']")
          end.value = "2024-11-03T01:20:00"
          end.dispatchEvent(new Event("input", { bubbles: true }))
          end.dispatchEvent(new Event("change", { bubbles: true }))
        JAVASCRIPT

        expect(page).to have_no_current_path(/after_at=/)
        query = Rack::Utils.parse_query(URI.parse(page.current_url).query)
        expect(query).to eq(
          "chart_start" => "2024-11-03T01:45:00-04:00",
          "chart_end" => "2024-11-03T01:20:00-05:00"
        )
      end
    end
  end

  it "permits a start edit across an ordered fall-back fold range" do
    with_time_zone("America/New_York") do
      with_browser_time_zone("America/New_York") do
        visit good_job.performance_index_path(
          chart_start: "2024-11-03T00:30:00-04:00",
          chart_end: "2024-11-03T01:15:00-05:00"
        )

        initial_state = page.evaluate_script(<<~JAVASCRIPT)
          (() => {
            const start = document.querySelector("[data-performance-range-target='startInput']")
            const end = document.querySelector("[data-performance-range-target='endInput']")
            return {
              endMinimum: end.min,
              startMaximum: start.max,
              valueMilliseconds: [start.valueAsNumber, end.valueAsNumber],
            }
          })()
        JAVASCRIPT

        expect(initial_state).to eq(
          "endMinimum" => "1000-01-01T00:00:00",
          "startMaximum" => "9999-12-31T23:59:59",
          "valueMilliseconds" => [
            Time.utc(2024, 11, 3, 0, 30).to_i * 1_000,
            Time.utc(2024, 11, 3, 1, 15).to_i * 1_000,
          ]
        )

        page.execute_script(<<~JAVASCRIPT)
          const url = new URL(window.location.href)
          url.searchParams.set("after_at", "ordered-fold-navigation-marker")
          window.history.replaceState({}, "", url)

          const start = document.querySelector("[data-performance-range-target='startInput']")
          start.value = "2024-11-03T01:45:00"
          start.dispatchEvent(new Event("input", { bubbles: true }))
          start.dispatchEvent(new Event("change", { bubbles: true }))
        JAVASCRIPT

        expect(page).to have_no_current_path(/after_at=/)
        query = Rack::Utils.parse_query(URI.parse(page.current_url).query)
        expect(query).to eq(
          "chart_start" => "2024-11-03T01:45:00-04:00",
          "chart_end" => "2024-11-03T01:15:00-05:00"
        )
      end
    end
  end

  it "rejects a browser-local endpoint in a DST gap" do
    with_browser_time_zone("America/New_York") do
      visit good_job.performance_index_path(
        chart_start: "2024-03-10T06:00:00Z",
        chart_end: "2024-03-10T08:00:00Z"
      )

      page.execute_script(<<~JAVASCRIPT)
        const start = document.querySelector("[data-performance-range-target='startInput']")
        start.value = "2024-03-10T02:30:00"
        start.dispatchEvent(new Event("input", { bubbles: true }))
        start.dispatchEvent(new Event("change", { bubbles: true }))
      JAVASCRIPT

      expect(page).to have_no_current_path(/chart_(?:range|start|end|time_zone)=/)
      expect(page).to have_css(".performance-range-key", text: "24h")
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

  it "serializes an upper-edge drag without crossing the four-digit canonical boundary" do
    with_time_zone("America/Toronto") do
      expected_start = "9999-12-31T23:54:59-05:00"
      expected_end = "9999-12-31T23:59:59-05:00"
      visit good_job.performance_index_path(
        after_at: "drag-navigation-marker",
        chart_start: expected_start,
        chart_end: expected_end
      )

      chart_area = page.evaluate_script("Chart.getChart(document.querySelector('[data-chart-target=\"canvas\"]')).chartArea")
      canvas_rect = page.evaluate_script("document.querySelector('[data-chart-target=\"canvas\"]').getBoundingClientRect().toJSON()")
      y = canvas_rect.fetch("y") + ((chart_area.fetch("top") + chart_area.fetch("bottom")) / 2)
      start_x = canvas_rect.fetch("x") + chart_area.fetch("left") + 1
      end_x = canvas_rect.fetch("x") + chart_area.fetch("right") - 1

      page.driver.browser.mouse.move(x: start_x, y: y)
      page.driver.browser.mouse.down
      page.driver.browser.mouse.move(x: end_x, y: y, steps: 5)
      page.driver.browser.mouse.up

      expect(page).to have_no_current_path(/after_at=/)
      expect(page).to have_current_path(/chart_start=/)
      expect(page).to have_css(".performance-range-key", text: "Custom")

      query = Rack::Utils.parse_query(URI.parse(page.current_url).query)
      expect(query).to eq("chart_start" => expected_start, "chart_end" => expected_end)
      expect(query.values).to all(match(GoodJob::PerformanceRange::TIMESTAMP_PATTERN))
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

  def with_browser_time_zone(zone_name)
    page.driver.browser.page.command("Emulation.setTimezoneOverride", timezoneId: zone_name)
    yield
  ensure
    page.driver.browser.page.command("Emulation.setTimezoneOverride", timezoneId: "UTC")
  end

  def with_time_zone(zone_name)
    original_zone = Time.zone_default
    Time.zone_default = Time.find_zone!(zone_name)
    yield
  ensure
    Time.zone_default = original_zone
  end
end
