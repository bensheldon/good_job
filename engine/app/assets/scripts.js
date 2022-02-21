GoodJob = {
  // Register functions to execute when the DOM is ready
  ready: (callback) => {
    if (document.readyState != "loading"){
      callback()
    } else {
      document.addEventListener("DOMContentLoaded", callback)
    }
  },

  init: () => {
    GoodJob.updateSettings()
    GoodJob.addListeners()
    GoodJob.pollUpdates()
  },

  addListeners() {
    const gjActionEls = document.querySelectorAll('[data-gj-action]')

    for (let i = 0; i < gjActionEls.length; i++) {
      const el = gjActionEls[i]
      const [eventName, func] = el.dataset.gjAction.split('#')

      el.addEventListener(eventName, GoodJob[func])
    }
  },

  updateSettings() {
    const queryString = window.location.search
    const urlParams = new URLSearchParams(queryString)

    // livepoll interval and enablement
    if (urlParams.has('poll')) {
      GoodJob.pollEnabled = true
      GoodJob.pollInterval = parseInt(urlParams.get('poll'))
      GoodJob.setStorage('pollInterval', GoodJob.pollInterval)
    } else {
      GoodJob.pollEnabled = GoodJob.getStorage('pollEnabled') || false
      GoodJob.pollInterval = GoodJob.getStorage('pollInterval') || 5000 // default 5sec
      if (GoodJob.pollEnabled) {
        // Update the UI element
        document.getElementById('toggle-poll').checked = true
      }
    }
  },

  togglePoll: (ev) => {
    GoodJob.pollEnabled = ev.currentTarget.checked
    GoodJob.setStorage('pollEnabled', GoodJob.pollEnabled)
  },

  pollUpdates: () => {
    setTimeout(() => {
      if (GoodJob.pollEnabled == true) {
        fetch(window.location.href)
          .then(resp => resp.text())
          .then(GoodJob.updateContent)
          .finally(GoodJob.pollUpdates)
      } else {
        GoodJob.pollUpdates()
      }
    }, GoodJob.pollInterval)
  },

  updateContent: (newContent) => {
    const domParser = new DOMParser()
    const parsedDOM = domParser.parseFromString(newContent, "text/html")

    const newElements = parsedDOM.querySelectorAll('[data-gj-poll-replace]')

    for (let i = 0; i < newElements.length; i++) {
      const newEl = newElements[i]
      const oldEl = document.getElementById(newEl.id)

      if (oldEl) {
        oldEl.replaceWith(newEl)
      }
    }
  },

  getStorage: (key) => {
    const value = localStorage.getItem('goodjob-' + key)

    if (value === 'true') { return true }
    else if (value === 'false') { return false }
    else { return value }
  },

  setStorage: (key, value) => {
    localStorage.setItem('goodjob-' + key, value)
  }
};

GoodJob.ready(GoodJob.init)
