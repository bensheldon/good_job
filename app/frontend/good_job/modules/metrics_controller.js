import { Controller } from "stimulus"
export default class extends Controller {
  static values = {
    primaryNavUrl: String,
  }
  static targets = [ "jobsCount", "batchesCount", "cronEntriesCount"]

  connect() {
    this.display_primary_nav_metrics()
  }

  async display_primary_nav_metrics() {
    const response = await fetch(this.primaryNavUrlValue);
    const result = await response.json()
    this.jobsCountTarget.textContent = result.jobsCount
    this.batchesCountTarget.textContent = result.batchesCount
    this.cronEntriesCountTarget.textContent = result.cronEntriesCount
  }
}
