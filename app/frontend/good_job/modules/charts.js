import htmlLegendPlugin from "html_legend_plugin";

function renderCharts(animate) {
  const charts = document.querySelectorAll('.chart');

  for (let i = 0; i < charts.length; i++) {
    const chartEl = charts[i];
    const chartData = JSON.parse(chartEl.dataset.json);
    chartData.options ||= {};

    if (chartData.options.plugins?.legend?.vertical) {
      chartData.plugins = [htmlLegendPlugin];
      chartData.options.plugins = {
        ...chartData.options.plugins,
        legend: {
          display: false,
        }
      }
    }
    chartData.options.animation = animate;
    chartData.options.responsive = true;
    chartData.options.maintainAspectRatio = false;

    const ctx = chartEl.getContext('2d');
    const chart = new Chart(ctx, chartData);
  }
}

export { renderCharts as default };
