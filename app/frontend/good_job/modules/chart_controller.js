import { Controller } from "stimulus"

const MINIMUM_RANGE_SELECTION_WIDTH = 8

const generateListItem = (item) => {
  const li = document.createElement('li');
  li.className = 'd-flex align-items-center text-nowrap mb-2';

  const boxSpan = document.createElement('span');
  boxSpan.className = 'legend-item-color-box';
  boxSpan.style.background = item.fillStyle;
  boxSpan.style.borderColor = item.strokeStyle;
  boxSpan.style.borderWidth = item.lineWidth + 'px';

  const textContainer = document.createElement('p');
  textContainer.className = 'item-text m-0 small';
  textContainer.style.color = item.fontColor;
  textContainer.style.textDecoration = item.hidden ? 'line-through' : '';

  const text = document.createTextNode(item.text);
  textContainer.appendChild(text);

  li.appendChild(boxSpan);
  li.appendChild(textContainer);

  return li;
}

export default class extends Controller {
  static values = {
    config: Object,
  }
  static targets = ["canvas", "legend"]

  connect() {
    this.#renderChart()
    this.#connectRangeSelection()
  }

  disconnect() {
    this.#disconnectRangeSelection()

    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  }

  #renderChart(animate = true) {
    const {goodJob, ...chartData} = this.configValue
    this.goodJobChart = goodJob || {}
    this.#localizeTimeSeriesLabels(chartData)

    chartData.options ||= {}

    if (this.hasLegendTarget) {
      const legendElement = this.legendTarget
      chartData.plugins = [{
        id: 'htmlLegend',
        afterUpdate(chart, _args, _options) {
          const {type} = chart.config

          while (legendElement.firstChild) {
            legendElement.firstChild.remove()
          }

          const items = chart.options.plugins.legend.labels.generateLabels(chart)
          items.forEach(item => {
            const li = generateListItem(item)
            legendElement.appendChild(li)

            li.onclick = () => {
              if (type === 'pie' || type === 'doughnut') {
                chart.toggleDataVisibility(item.index)
              } else {
                chart.setDatasetVisibility(item.datasetIndex, !chart.isDatasetVisible(item.datasetIndex))
              }
              chart.update()
            }
          })
        }
      }]
      chartData.options.plugins = {
        ...chartData.options.plugins,
        legend: { display: false },
      }
    }

    chartData.options.animation = animate
    chartData.options.responsive = true
    chartData.options.maintainAspectRatio = false

    const ctx = this.canvasTarget.getContext('2d')
    this.chart = new Chart(ctx, chartData)
  }

  #localizeTimeSeriesLabels(chartData) {
    if (!this.goodJobChart.time_series) return

    try {
      const timestamps = this.goodJobChart.timestamps
      const boundaryTimestamps = [this.goodJobChart.range_start, this.goodJobChart.range_end]
      const dates = [...boundaryTimestamps, ...timestamps].map(timestamp => new Date(timestamp))
      const representable = dates.every(date => {
        const year = date.getFullYear()
        return Number.isFinite(date.getTime()) && year >= 1000 && year <= 9999
      })
      if (!representable) return

      const options = {
        hour: "2-digit",
        hourCycle: "h23",
        minute: "2-digit",
      }
      if (this.goodJobChart.timestamp_label_style === "date_time") {
        options.day = "numeric"
        options.month = "short"
      }
      const formatter = new Intl.DateTimeFormat(document.documentElement.lang, options)
      if (!formatter.resolvedOptions().timeZone) return

      chartData.data.labels = dates.slice(boundaryTimestamps.length).map(date => formatter.format(date))
    } catch (_error) {
      // Preserve application-zone labels when browser localization is unavailable.
    }
  }

  #connectRangeSelection() {
    if (!this.goodJobChart.time_series || this.goodJobChart.timestamps.length < 2) return

    this.rangeSelectionPointerDown = this.#startRangeSelection.bind(this)
    this.canvasTarget.addEventListener("pointerdown", this.rangeSelectionPointerDown)
  }

  #disconnectRangeSelection() {
    if (this.rangeSelectionPointerDown) {
      this.canvasTarget.removeEventListener("pointerdown", this.rangeSelectionPointerDown)
      this.rangeSelectionPointerDown = null
    }

    this.#removeRangeSelectionEvents()
    this.#removeRangeSelectionElement()
  }

  #startRangeSelection(event) {
    if (event.button !== 0 || !this.#eventInChartArea(event)) return

    event.preventDefault()

    const position = this.#eventPosition(event)
    this.rangeSelectionStartX = position.x
    this.rangeSelectionCurrentX = position.x

    this.rangeSelectionPointerMove = this.#updateRangeSelection.bind(this)
    this.rangeSelectionPointerUp = this.#finishRangeSelection.bind(this)
    this.rangeSelectionPointerCancel = this.#cancelRangeSelection.bind(this)

    this.canvasTarget.setPointerCapture(event.pointerId)
    this.canvasTarget.addEventListener("pointermove", this.rangeSelectionPointerMove)
    this.canvasTarget.addEventListener("pointerup", this.rangeSelectionPointerUp)
    this.canvasTarget.addEventListener("pointercancel", this.rangeSelectionPointerCancel)

    this.#renderRangeSelection()
  }

  #updateRangeSelection(event) {
    this.rangeSelectionCurrentX = this.#eventPosition(event).x
    this.#renderRangeSelection()
  }

  #finishRangeSelection(event) {
    this.rangeSelectionCurrentX = this.#eventPosition(event).x
    this.#removeRangeSelectionEvents()
    this.#removeRangeSelectionElement()

    if (Math.abs(this.rangeSelectionCurrentX - this.rangeSelectionStartX) < MINIMUM_RANGE_SELECTION_WIDTH) return

    const [startParameter, endParameter] = this.#selectedRange()
    const startTime = new Date(startParameter).getTime()
    const endTime = new Date(endParameter).getTime()
    if (!startParameter || !endParameter || startTime >= endTime) return

    const url = new URL(window.location.href)
    url.searchParams.set("chart_start", startParameter)
    url.searchParams.set("chart_end", endParameter)
    url.searchParams.delete("chart_range")
    url.searchParams.delete("after_at")
    url.searchParams.delete("after_id")

    if (window.Turbo) {
      window.Turbo.visit(url.toString())
    } else {
      window.location.assign(url.toString())
    }
  }

  #cancelRangeSelection() {
    this.#removeRangeSelectionEvents()
    this.#removeRangeSelectionElement()
  }

  #removeRangeSelectionEvents() {
    if (this.rangeSelectionPointerMove) {
      this.canvasTarget.removeEventListener("pointermove", this.rangeSelectionPointerMove)
      this.rangeSelectionPointerMove = null
    }

    if (this.rangeSelectionPointerUp) {
      this.canvasTarget.removeEventListener("pointerup", this.rangeSelectionPointerUp)
      this.rangeSelectionPointerUp = null
    }

    if (this.rangeSelectionPointerCancel) {
      this.canvasTarget.removeEventListener("pointercancel", this.rangeSelectionPointerCancel)
      this.rangeSelectionPointerCancel = null
    }
  }

  #renderRangeSelection() {
    const chartArea = this.chart.chartArea
    const startX = this.#clamp(this.rangeSelectionStartX, chartArea.left, chartArea.right)
    const currentX = this.#clamp(this.rangeSelectionCurrentX, chartArea.left, chartArea.right)
    const left = Math.min(startX, currentX)
    const width = Math.abs(currentX - startX)
    const selectionElement = this.#rangeSelectionElement()

    selectionElement.style.left = `${left}px`
    selectionElement.style.top = `${chartArea.top}px`
    selectionElement.style.width = `${width}px`
    selectionElement.style.height = `${chartArea.bottom - chartArea.top}px`
  }

  #rangeSelectionElement() {
    if (!this.selectionElement) {
      this.selectionElement = document.createElement("div")
      this.selectionElement.className = "chart-range-selection"
      this.canvasTarget.parentElement.appendChild(this.selectionElement)
    }

    return this.selectionElement
  }

  #removeRangeSelectionElement() {
    if (this.selectionElement) {
      this.selectionElement.remove()
      this.selectionElement = null
    }
  }

  #selectedRange() {
    const chartArea = this.chart.chartArea
    const startX = this.#clamp(this.rangeSelectionStartX, chartArea.left, chartArea.right)
    const currentX = this.#clamp(this.rangeSelectionCurrentX, chartArea.left, chartArea.right)
    const firstIndex = this.#timestampIndexForPixel(Math.min(startX, currentX))
    const lastIndex = this.#timestampIndexForPixel(Math.max(startX, currentX))
    const timestamps = this.goodJobChart.timestamps

    // Clamp partial edge buckets to the exact page range so drag selection cannot
    // widen the half-open interval represented by the toolbar and server query.
    const firstBucketStart = new Date(timestamps[firstIndex]).getTime()
    const rangeStart = new Date(this.goodJobChart.range_start).getTime()
    const rangeEnd = new Date(this.goodJobChart.range_end).getTime()
    const nextTimestamp = timestamps[lastIndex + 1]
    const startParameter = firstBucketStart < rangeStart ? this.goodJobChart.range_start : timestamps[firstIndex]
    const endParameter = nextTimestamp && new Date(nextTimestamp).getTime() < rangeEnd ?
      nextTimestamp : this.goodJobChart.range_end

    return [startParameter, endParameter]
  }

  #timestampIndexForPixel(pixel) {
    const chartArea = this.chart.chartArea
    const timestamps = this.goodJobChart.timestamps
    const ratio = (pixel - chartArea.left) / (chartArea.right - chartArea.left)
    const index = Math.round(ratio * (timestamps.length - 1))

    return this.#clamp(index, 0, timestamps.length - 1)
  }

  #eventInChartArea(event) {
    const position = this.#eventPosition(event)
    const chartArea = this.chart.chartArea

    return position.x >= chartArea.left &&
      position.x <= chartArea.right &&
      position.y >= chartArea.top &&
      position.y <= chartArea.bottom
  }

  #eventPosition(event) {
    return Chart.helpers.getRelativePosition(event, this.chart)
  }

  #clamp(value, min, max) {
    return Math.min(Math.max(value, min), max)
  }
}
