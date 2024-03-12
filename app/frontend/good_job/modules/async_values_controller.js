import { Controller } from "stimulus"
export default class extends Controller {
  static values = {
    url: String,
  }
  static targets = [ "values" ]

  connect() {
    this.display_values()
  }

  async display_values() {
    const response = await fetch(this.urlValue);
    const result = await response.json()
    this.valuesTargets.forEach((target) => {
      target.textContent = result[target.dataset['asyncValuesKey']]
    })
  }
}
