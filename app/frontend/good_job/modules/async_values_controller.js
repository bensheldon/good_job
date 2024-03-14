import {Controller} from "stimulus"

// Fetches JSON values from the server and updates the targets with the response.
export default class extends Controller {
  static values = {
    url: String,
  }
  static targets = ["value"]

  connect() {
    this.#fetch();
  }

  async #fetch() {
    const data = await fetch(this.urlValue).then(response => response.json())
    this.valueTargets.forEach((target) => {
      target.textContent = data[target.dataset['asyncValuesKey']];
      target.classList.remove('d-none');

      // When `data-async-values-zero-class="css-class"` is set, add `css-class` to the target if the value is "0"
      if (target.dataset['asyncValuesZeroClass']) {
        const className = target.dataset['asyncValuesZeroClass'];
        if (data[target.dataset['asyncValuesKey']] === "0") {
          target.classList.add(className);
        } else {
          target.classList.remove(className);
        }
      }
    });
  }
}
