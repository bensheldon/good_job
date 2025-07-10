import {Controller} from "stimulus"

export default class extends Controller {
  submit() {
    this.element.requestSubmit();
  }

  reset() {
    this.element.reset();
  }
}
