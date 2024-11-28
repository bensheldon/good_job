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

const htmlLegendPlugin = {
  id: 'htmlLegend',
  afterUpdate(chart, _args, _options) {
    const {type} = chart.config;
    const ul = document.getElementById('chart-legend-ul');

    // Remove old legend items
    while (ul.firstChild) {
      ul.firstChild.remove();
    }

    // Reuse the built-in legendItems generator
    const items = chart.options.plugins.legend.labels.generateLabels(chart);

    items.forEach(item => {
      const li = generateListItem(item);
      ul.appendChild(li);

      li.onclick = () => {
        if (type === 'pie' || type === 'doughnut') {
          // Pie and doughnut charts only have a single dataset and visibility is per item
          chart.toggleDataVisibility(item.index);
        } else {
          chart.setDatasetVisibility(item.datasetIndex, !chart.isDatasetVisible(item.datasetIndex));
        }
        chart.update();
      };
    });
  }
};

export { htmlLegendPlugin as default };
