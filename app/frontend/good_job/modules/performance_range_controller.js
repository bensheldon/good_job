import { Controller } from "stimulus"

// Enhances the Performance range form while leaving parsing and validation authoritative on the server.
export default class extends Controller {
  static targets = [
    "endCanonicalInput",
    "endInput",
    "endLabel",
    "startCanonicalInput",
    "startInput",
    "startLabel",
    "timeZoneInput",
    "timeZoneLabel",
  ]
  static values = {
    applicationTimeZone: String,
    endFallback: String,
    endLabel: String,
    endTimestamp: String,
    labelStyle: String,
    maximum: String,
    minimum: String,
    startFallback: String,
    startLabel: String,
    startTimestamp: String,
  }

  // Rebuild from immutable server values so Turbo cache restoration cannot apply localization twice.
  connect() {
    this.#restoreApplicationTimeZoneFallback()
    this.#configureFormatter()
    this.#enhanceBrowserTimeZone()

    this.backwardClockTransition = this.#crossesBackwardClockTransition()
    this.#configureExactFormatter()
    this.reciprocalConstraints =
      !this.backwardClockTransition &&
      this.startInputTarget.valueAsNumber < this.endInputTarget.valueAsNumber
    this.constrain()
  }

  // Remember which civil endpoint must be resolved in the browser timezone by the server.
  edit(event) {
    if (this.browserTimeZone) event.currentTarget.dataset.performanceRangeEdited = "true"
  }

  // Prevent the native controls from accepting equal or reversed ordinary wall-clock endpoints.
  constrain() {
    const startMilliseconds = this.#civilMilliseconds(this.startInputTarget.value)
    const endMilliseconds = this.#civilMilliseconds(this.endInputTarget.value)

    // Offset-free native fields cannot order repeated wall-clock values. Keep a known backward
    // transition relaxed; otherwise restore reciprocal constraints once edits are ordered.
    if (
      !this.reciprocalConstraints &&
      !this.backwardClockTransition &&
      startMilliseconds !== null &&
      endMilliseconds !== null &&
      startMilliseconds < endMilliseconds
    ) {
      this.reciprocalConstraints = true
    }

    if (this.reciprocalConstraints) {
      this.startInputTarget.max = this.#offsetLocal(
        this.endInputTarget.value,
        -1,
        this.maximumValue,
      )
      this.endInputTarget.min = this.#offsetLocal(
        this.startInputTarget.value,
        1,
        this.minimumValue,
      )
    } else {
      this.startInputTarget.max = this.maximumValue
      this.endInputTarget.min = this.minimumValue
    }

    if (this.formatter) {
      this.startLabelTarget.textContent = this.#formatEndpointLabel(
        this.startInputTarget,
        this.startTimestampValue,
      )
      this.endLabelTarget.textContent = this.#formatEndpointLabel(
        this.endInputTarget,
        this.endTimestampValue,
      )
    }
  }

  // Prepare every submission path, including an implicit submit that bypasses endpoint change.
  prepareSubmission() {
    if (this.browserTimeZone) {
      const endpointPairs = [
        [this.startInputTarget, this.startCanonicalInputTarget],
        [this.endInputTarget, this.endCanonicalInputTarget],
      ]
      let edited = false

      endpointPairs.forEach(([input, canonicalInput]) => {
        if (input.dataset.performanceRangeEdited !== "true") return

        canonicalInput.value = input.value
        edited = true
      })

      if (edited) {
        this.timeZoneInputTarget.value = this.browserTimeZone
        this.timeZoneInputTarget.disabled = false
      }
    }
  }

  // Submit exact untouched endpoints and browser-local civil values only for edited endpoints.
  submitRange() {
    if (!this.element.checkValidity()) return

    this.element.requestSubmit()
  }

  // Open the browser picker from a click on the rendered field when supported.
  openPicker(event) {
    const input = event.currentTarget
    if (typeof input.showPicker !== "function") return

    try {
      input.focus()
      input.showPicker()
      event.preventDefault()
    } catch (_error) {
      // Let the input's native click behavior continue when showPicker is unavailable here.
    }
  }

  #restoreApplicationTimeZoneFallback() {
    this.browserTimeZone = null
    this.startInputTarget.name = "chart_start"
    this.endInputTarget.name = "chart_end"
    this.startInputTarget.value = this.startFallbackValue
    this.endInputTarget.value = this.endFallbackValue
    delete this.startInputTarget.dataset.performanceRangeEdited
    delete this.endInputTarget.dataset.performanceRangeEdited

    this.startCanonicalInputTarget.value = this.startTimestampValue
    this.startCanonicalInputTarget.disabled = true
    this.endCanonicalInputTarget.value = this.endTimestampValue
    this.endCanonicalInputTarget.disabled = true
    this.timeZoneInputTarget.value = ""
    this.timeZoneInputTarget.disabled = true

    this.startLabelTarget.textContent = this.startLabelValue
    this.endLabelTarget.textContent = this.endLabelValue
    this.timeZoneLabelTarget.textContent = this.applicationTimeZoneValue
  }

  #configureFormatter() {
    this.formatter = null

    try {
      // The input already represents a wall clock. UTC prevents Intl from shifting it again.
      this.formatter = new Intl.DateTimeFormat(document.documentElement.lang, {
        day: "numeric",
        hour: "2-digit",
        hourCycle: "h23",
        minute: "2-digit",
        month: "short",
        second: "2-digit",
        timeZone: "UTC",
        ...(this.labelStyleValue === "date_time_year" ? { year: "numeric" } : {}),
      })
    } catch (_error) {
      // Server-rendered application-zone values and labels remain accurate without Intl.
    }
  }

  #configureExactFormatter() {
    this.exactFormatter = null
    if (!this.backwardClockTransition) return

    for (const timeZoneName of ["shortOffset", "short"]) {
      try {
        this.exactFormatter = new Intl.DateTimeFormat(document.documentElement.lang, {
          day: "numeric",
          hour: "2-digit",
          hourCycle: "h23",
          minute: "2-digit",
          month: "short",
          second: "2-digit",
          timeZoneName,
          ...(this.labelStyleValue === "date_time_year" ? { year: "numeric" } : {}),
        })
        return
      } catch (_error) {
        // Try the next supported timezone-name representation.
      }
    }
  }

  #enhanceBrowserTimeZone() {
    if (!this.formatter) return

    try {
      const browserTimeZone = new Intl.DateTimeFormat().resolvedOptions().timeZone
      const startValue = this.#browserLocalValue(this.startTimestampValue)
      const endValue = this.#browserLocalValue(this.endTimestampValue)
      if (!browserTimeZone || !startValue || !endValue) return

      this.startInputTarget.value = startValue
      this.endInputTarget.value = endValue
      this.startInputTarget.removeAttribute("name")
      this.endInputTarget.removeAttribute("name")
      this.startCanonicalInputTarget.disabled = false
      this.endCanonicalInputTarget.disabled = false
      this.timeZoneLabelTarget.textContent = browserTimeZone
      this.browserTimeZone = browserTimeZone
    } catch (_error) {
      // Keep the whole control in its application-zone fallback when enhancement is unavailable.
    }
  }

  #browserLocalValue(timestamp) {
    const date = new Date(timestamp)
    if (!Number.isFinite(date.getTime())) return null

    const year = date.getFullYear()
    if (year < 1000 || year > 9999) return null

    return [
      String(year).padStart(4, "0"),
      "-",
      String(date.getMonth() + 1).padStart(2, "0"),
      "-",
      String(date.getDate()).padStart(2, "0"),
      "T",
      String(date.getHours()).padStart(2, "0"),
      ":",
      String(date.getMinutes()).padStart(2, "0"),
      ":",
      String(date.getSeconds()).padStart(2, "0"),
    ].join("")
  }

  // Convert a wall-clock value to a browser-zone-independent civil timestamp.
  #civilMilliseconds(value) {
    const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?$/.exec(value)
    if (!match) return null

    const [, year, month, day, hour, minute, second = "00"] = match
    const milliseconds = Date.UTC(
      Number(year),
      Number(month) - 1,
      Number(day),
      Number(hour),
      Number(minute),
      Number(second),
    )
    const normalized = `${year}-${month}-${day}T${hour}:${minute}:${second}`

    return this.#localValue(milliseconds) === normalized ? milliseconds : null
  }

  // Native civil fields cannot express the repeated hour in a backward clock transition.
  #crossesBackwardClockTransition() {
    const exactStart = new Date(this.startTimestampValue).getTime()
    const exactEnd = new Date(this.endTimestampValue).getTime()
    const civilStart = this.#civilMilliseconds(this.startInputTarget.value)
    const civilEnd = this.#civilMilliseconds(this.endInputTarget.value)
    if (![exactStart, exactEnd, civilStart, civilEnd].every(Number.isFinite)) return false

    return exactEnd - exactStart > civilEnd - civilStart
  }

  #formatLabel(value) {
    const milliseconds = this.#civilMilliseconds(value)
    return milliseconds === null ? "—" : this.formatter.format(new Date(milliseconds))
  }

  #formatEndpointLabel(input, timestamp) {
    if (
      this.exactFormatter &&
      input.dataset.performanceRangeEdited !== "true"
    ) {
      const date = new Date(timestamp)
      if (Number.isFinite(date.getTime())) return this.exactFormatter.format(date)
    }

    return this.#formatLabel(input.value)
  }

  // Move a civil value by whole seconds and clamp it to the four-digit-year bounds.
  #offsetLocal(value, seconds, fallback) {
    const milliseconds = this.#civilMilliseconds(value)
    if (milliseconds === null) return fallback

    const minimum = this.#civilMilliseconds(this.minimumValue)
    const maximum = this.#civilMilliseconds(this.maximumValue)
    const bounded = Math.min(maximum, Math.max(minimum, milliseconds + (seconds * 1000)))

    return this.#localValue(bounded)
  }

  // Serialize a civil timestamp in the normalized shape expected by datetime-local.
  #localValue(milliseconds) {
    return new Date(milliseconds).toISOString().slice(0, 19)
  }
}
