function renderCharts(animate) {
  const charts = document.querySelectorAll('.chart');

  for (let i = 0; i < charts.length; i++) {
    const chartEl = charts[i];
    const chartData = JSON.parse(chartEl.dataset.json);

    const ctx = chartEl.getContext('2d');
    const chart = new Chart(ctx, {
      type: 'line',
      data: {
        labels: chartData.labels,
        datasets: chartData.datasets
      },
      options: {
        animation: animate,
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          y: {
            beginAtZero: true
          }
        }
      }
    });
  }
}

export { renderCharts as default };
