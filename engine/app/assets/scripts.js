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
    } else {
      GoodJob.pollEnabled = false
      GoodJob.pollInterval = 5000 // default 5sec
    }
  },

  togglePoll: (ev) => {
    GoodJob.pollEnabled = ev.currentTarget.checked
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
        oldEl.parentNode.replaceChild(newEl, oldEl)
      }
    }
  }
};

GoodJob.ready(GoodJob.init)
