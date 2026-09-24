import { Controller } from "stimulus"

const MINIMUM_POLL_INTERVAL = 1
const STORAGE_KEY = "good_job-live_poll"

export default class extends Controller {
  static targets = ["checkbox"]

  #interval = null

  connect() {
    const stored = localStorage.getItem(STORAGE_KEY)
    if (stored && !this.checkboxTarget.checked) {
      this.checkboxTarget.checked = true
      this.checkboxTarget.value = stored
    }
    this.#togglePolling()
  }

  disconnect() {
    if (this.#interval) {
      clearInterval(this.#interval)
      this.#interval = null
    }
  }

  toggle() {
    this.#togglePolling()
  }

  #togglePolling() {
    const enabled = this.checkboxTarget.checked
    const pollIntervalMs = Math.max(parseInt(this.checkboxTarget.value), MINIMUM_POLL_INTERVAL) * 1000

    if (this.#interval) {
      clearInterval(this.#interval)
      this.#interval = null
    }

    if (enabled) {
      localStorage.setItem(STORAGE_KEY, this.checkboxTarget.value)
      this.#interval = setInterval(() => this.#refreshPage(), pollIntervalMs)
    } else {
      localStorage.removeItem(STORAGE_KEY)
    }
  }

  async #refreshPage() {
    const resp = await fetch(window.location.href)
    const newContent = await resp.text()

    const domParser = new DOMParser()
    const newDom = domParser.parseFromString(newContent, "text/html")

    newDom.querySelectorAll('[data-live-poll-region]').forEach((newElement) => {
      const regionName = newElement.getAttribute('data-live-poll-region')
      const originalElement = document.querySelector(`[data-live-poll-region="${regionName}"]`)
      if (originalElement) {
        this.#restoreTabs(originalElement, newElement)
      }
    })
  }

  // Re-select any Bootstrap tabs that were active before a region is replaced
  #restoreTabs(originalElement, newElement) {
    const activeTargets = [...originalElement.querySelectorAll('.nav-link.active[data-bs-toggle]')]
      .map((tab) => tab.getAttribute('data-bs-target') || tab.getAttribute('href'))
    originalElement.replaceWith(newElement)
    activeTargets.forEach((target) => {
      const newTab = newElement.querySelector(`[data-bs-target="${target}"], [href="${target}"]`)
      if (newTab) {
        bootstrap.Tab.getOrCreateInstance(newTab).show()
      }
    })
  }
}
