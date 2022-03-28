/*jshint esversion: 6, strict: false */
const GOOD_JOB_DEFAULT_POLL_INTERVAL_SECONDS = 30;
const GOOD_JOB_MINIMUM_POLL_INTERVAL = 1000;

const GoodJob = {
  // Register functions to execute when the DOM is ready
  ready: (callback) => {
    if (document.readyState !== "loading") {
      callback();
    } else {
      document.addEventListener("DOMContentLoaded", callback);
    }
  },

  init: () => {
    GoodJob.updateSettings();
    GoodJob.addListeners();
    GoodJob.pollUpdates();
    GoodJob.renderCharts(true);
  },

  addListeners: () => {
    const gjActionEls = document.querySelectorAll('[data-gj-action]');

    for (let i = 0; i < gjActionEls.length; i++) {
      const el = gjActionEls[i];
      const [eventName, func] = el.dataset.gjAction.split('#');

      el.addEventListener(eventName, GoodJob[func]);
    }
  },

  updateSettings: () => {
    const queryString = window.location.search;
    const urlParams = new URLSearchParams(queryString);

    // live poll interval and enablement
    if (urlParams.has('poll')) {
      const parsedInterval = (parseInt(urlParams.get('poll')) || GOOD_JOB_DEFAULT_POLL_INTERVAL_SECONDS) * 1000;
      GoodJob.pollInterval = Math.max(parsedInterval, GOOD_JOB_MINIMUM_POLL_INTERVAL);
      GoodJob.setStorage('pollInterval', GoodJob.pollInterval);

      GoodJob.pollEnabled = true;
    } else {
      GoodJob.pollInterval = GoodJob.getStorage('pollInterval') || (GOOD_JOB_DEFAULT_POLL_INTERVAL_SECONDS * 1000);
      GoodJob.pollEnabled = GoodJob.getStorage('pollEnabled') || false;
    }

    document.getElementById('toggle-poll').checked = GoodJob.pollEnabled;
  },

  togglePoll: (ev) => {
    GoodJob.pollEnabled = ev.currentTarget.checked;
    GoodJob.setStorage('pollEnabled', GoodJob.pollEnabled);
  },

  pollUpdates: () => {
    setTimeout(() => {
      if (GoodJob.pollEnabled === true) {
        fetch(window.location.href)
          .then(resp => resp.text())
          .then(GoodJob.updateContent)
          .finally(GoodJob.pollUpdates);
      } else {
        GoodJob.pollUpdates();
      }
    }, GoodJob.pollInterval);
  },

  updateContent: (newContent) => {
    const domParser = new DOMParser();
    const parsedDOM = domParser.parseFromString(newContent, "text/html");

    const newElements = parsedDOM.querySelectorAll('[data-gj-poll-replace]');

    for (let i = 0; i < newElements.length; i++) {
      const newEl = newElements[i];
      const oldEl = document.getElementById(newEl.id);

      if (oldEl) {
        oldEl.replaceWith(newEl);
      }
    }

    GoodJob.renderCharts(false);
  },

  renderCharts: (animate) => {
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
  },

  getStorage: (key) => {
    const value = localStorage.getItem('good_job-' + key);

    if (value === 'true') {
      return true;
    } else if (value === 'false') {
      return false;
    } else {
      return value;
    }
  },

  setStorage: (key, value) => {
    localStorage.setItem('good_job-' + key, value);
  }
};

GoodJob.ready(GoodJob.init);
