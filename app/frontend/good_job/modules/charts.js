function renderCharts(animate) {
  const charts = document.querySelectorAll('.chart');

  for (let i = 0; i < charts.length; i++) {
    const chartEl = charts[i];
    const chartData = JSON.parse(chartEl.dataset.json);
    const ctx = chartEl.getContext('2d');
    new Chart(ctx, chartData);
  }
}

export { renderCharts as default };
