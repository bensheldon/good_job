import { Controller } from "stimulus"

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
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  }

  #renderChart(animate = true) {
    const chartData = this.configValue
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
}
