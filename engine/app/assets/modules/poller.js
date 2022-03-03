/*jshint esversion: 6, strict: false */
import renderCharts from "charts";

// NOTE: this file is a bit disorganized. Please do not use it as a template for how to organize a JS module.

const DEFAULT_POLL_INTERVAL_SECONDS = 30;
const MINIMUM_POLL_INTERVAL = 1000;

function getStorage(key) {
  const value = localStorage.getItem('good_job-' + key);

  if (value === 'true') {
    return true;
  } else if (value === 'false') {
    return false;
  } else {
    return value;
  }
}

function setStorage(key, value) {
  localStorage.setItem('good_job-' + key, value);
}

function updatePageContent(newContent) {
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

  renderCharts(false);
}

function refreshPage() {
  fetch(window.location.href)
    .then(resp => resp.text())
    .then(updatePageContent);
}

const Poller = {
  start: () => {
    Poller.updateSettings();
    Poller.pollUpdates();

    const checkbox = document.querySelector('input[name="toggle-poll"]');
    checkbox.addEventListener('change', Poller.togglePoll)
  },

  togglePoll: (event) => {
    Poller.pollEnabled = event.currentTarget.checked;
    setStorage('pollEnabled', Poller.pollEnabled);
  },

  updateSettings: () => {
    const queryString = window.location.search;
    const urlParams = new URLSearchParams(queryString);

    if (urlParams.has('poll')) {
      const parsedInterval = (parseInt(urlParams.get('poll')) || DEFAULT_POLL_INTERVAL_SECONDS) * 1000;
      Poller.pollInterval = Math.max(parsedInterval, MINIMUM_POLL_INTERVAL);
      setStorage('pollInterval', Poller.pollInterval);

      Poller.pollEnabled = true;
    } else {
      Poller.pollInterval = getStorage('pollInterval') || (DEFAULT_POLL_INTERVAL_SECONDS * 1000);
      Poller.pollEnabled = getStorage('pollEnabled') || false;
    }

    document.getElementById('toggle-poll').checked = Poller.pollEnabled;
  },

  pollUpdates: () => {
    setTimeout(() => {
      if (Poller.pollEnabled === true) {
        refreshPage();
        Poller.pollUpdates();
      } else {
        Poller.pollUpdates();
      }
    }, Poller.pollInterval);
  },
};

export { Poller as default };
