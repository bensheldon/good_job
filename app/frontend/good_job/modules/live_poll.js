/*jshint esversion: 6, strict: false */
import renderCharts from "charts";

const MINIMUM_POLL_INTERVAL = 1;
const STORAGE_KEY = "live_poll";

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

function removeStorage(key) {
  localStorage.removeItem('good_job-' + key);
}

export default class LivePoll {
  start() {
    const checkbox = document.querySelector('input[name="live_poll"]');

    if (!checkbox.checked && getStorage(STORAGE_KEY)) {
      checkbox.checked = true;
      checkbox.value = getStorage(STORAGE_KEY)
    }

    checkbox.addEventListener('change', () => {
      this.togglePolling();
    });

    this.togglePolling();
  }

  togglePolling = () => {
    const checkbox = document.querySelector('input[name="live_poll"]');
    const enabled = checkbox.checked;
    const pollIntervalMilliseconds = Math.max(parseInt(checkbox.value), MINIMUM_POLL_INTERVAL) * 1000;

    if (this.interval) {
      clearInterval(this.interval);
      this.interval = null;
    }

    if (enabled) {
      setStorage(STORAGE_KEY, checkbox.value);
      this.interval = setInterval(LivePoll.refreshPage, pollIntervalMilliseconds);
    } else {
      removeStorage(STORAGE_KEY);
    }
  }

  static refreshPage() {
    fetch(window.location.href)
      .then(resp => resp.text())
      .then(LivePoll.updatePageContent);
  }

  static updatePageContent(newContent) {
    const domParser = new DOMParser();
    const newDom = domParser.parseFromString(newContent, "text/html");

    const newElements = newDom.querySelectorAll('[data-live-poll-region]');
    newElements.forEach((newElement) => {
      const regionName = newElement.getAttribute('data-live-poll-region');
      const originalElement = document.querySelector(`[data-live-poll-region="${regionName}"]`);

      originalElement.replaceWith(newElement);
    });

    renderCharts(false);
  }
}
