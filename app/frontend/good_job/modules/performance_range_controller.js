import { Controller } from "stimulus"

// Enhances the Performance range form while leaving parsing and validation authoritative on the server.
export default class extends Controller {
  static targets = ["endInput", "endLabel", "startInput", "startLabel"]
  static values = {
    maximum: String,
    minimum: String,
  }

  // Synchronize native constraints and rendered labels after Turbo navigation.
  connect() {
    this.formatter = new Intl.DateTimeFormat(document.documentElement.lang, {
      day: "numeric",
      hour: "2-digit",
      hourCycle: "h23",
      minute: "2-digit",
      month: "short",
      second: "2-digit",
      timeZone: "UTC",
    })
    this.reciprocalConstraints = this.startInputTarget.valueAsNumber < this.endInputTarget.valueAsNumber
    this.constrain()
  }

  // Prevent the native controls from accepting equal or reversed range endpoints.
  constrain() {
    const startMilliseconds = this.#civilMilliseconds(this.startInputTarget.value)
    const endMilliseconds = this.#civilMilliseconds(this.endInputTarget.value)

    // Offset-free native fields cannot order repeated wall-clock values. Preserve an exact
    // server-resolved fold interval until the edited values become ordinarily ordered.
    if (
      !this.reciprocalConstraints &&
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
    this.startLabelTarget.textContent = this.#formatLabel(this.startInputTarget.value)
    this.endLabelTarget.textContent = this.#formatLabel(this.endInputTarget.value)
  }

  // Navigate only after a committed native edit leaves both endpoints valid.
  submitRange() {
    if (this.element.checkValidity()) this.element.requestSubmit()
  }

  // Open the browser picker from a click on the compact rendered field when supported.
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

  // Format the compact display without applying the browser's timezone.
  #formatLabel(value) {
    const milliseconds = this.#civilMilliseconds(value)
    return milliseconds === null ? "—" : this.formatter.format(new Date(milliseconds))
  }

  // Move a local value by whole seconds and clamp it to the four-digit-year bounds.
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
