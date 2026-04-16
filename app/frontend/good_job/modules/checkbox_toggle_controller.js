import { Controller } from "stimulus"

export default class extends Controller {
  static targets = ["all", "each", "show"]

  toggleAll() {
    const checked = this.allTarget.checked
    this.eachTargets.forEach(cb => cb.checked = checked)
    this.showTargets.forEach(el => {
      el.classList.toggle("d-none", !checked)
      el.disabled = !checked
    })
  }

  syncAll() {
    const checkedCount = this.eachTargets.filter(cb => cb.checked).length
    const allChecked = checkedCount === this.eachTargets.length
    const indeterminate = !allChecked && checkedCount > 0

    this.allTarget.checked = allChecked
    this.allTarget.indeterminate = indeterminate

    this.showTargets.forEach(el => {
      el.classList.toggle("d-none", !allChecked)
      el.disabled = !allChecked
    })
  }
}
