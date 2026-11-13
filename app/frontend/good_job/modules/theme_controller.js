// hello_controller.js
import { Controller } from "stimulus"
export default class extends Controller {
  static targets = [ "dropdown", "button" ]

  connect() {
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
      if (this.getStoredTheme() === 'auto') {
        this.setTheme('auto');
      }
    });

    this.setTheme(this.getStoredTheme());
  }

  change(event) {
    const theme = event.params.value;
    localStorage.setItem('good_job-theme', theme);
    this.setTheme(theme);
  }

  // Follows a theme chosen in another tab.
  sync(event) {
    if (event.key === 'good_job-theme' || event.key === null) {
      this.setTheme(this.getStoredTheme());
    }
  }

  setTheme(theme) {
    document.documentElement.setAttribute('data-bs-theme', theme === 'auto' ? this.autoTheme() : theme);

    this.buttonTargets.forEach((button) => {
      button.classList.remove('active');
      if (button.dataset.themeValueParam === theme) {
        button.classList.add('active');
      }
    });

    const svg = this.buttonTargets.filter(b => b.matches(".active"))[0]?.querySelector('svg');
    this.dropdownTarget.querySelector('svg').outerHTML = svg.outerHTML;
  }

  // Matches the layout's inline script, which follows the system unless
  // light or dark is stored.
  getStoredTheme() {
    const theme = localStorage.getItem('good_job-theme');
    return ["light", "dark"].includes(theme) ? theme : 'auto';
  }

  autoTheme() {
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
  }
}
