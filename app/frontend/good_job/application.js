/*jshint esversion: 6, strict: false */

import "turbo";
import { Application } from "stimulus";
window.Stimulus = Application.start();

import FormController from "form_controller";
Stimulus.register("form", FormController);
import ThemeController from "theme_controller";
Stimulus.register("theme", ThemeController);
import AsyncValuesController from "async_values_controller";
Stimulus.register("async-values", AsyncValuesController);

import renderCharts from "charts";
import checkboxToggle from "checkbox_toggle";
import showToasts from "toasts";
import setupPopovers from "popovers";
import LivePoll from "live_poll";

window.document.addEventListener("turbo:load", function() {
  renderCharts();
  showToasts();
  setupPopovers();
  checkboxToggle();

  const livePoll = new LivePoll
  livePoll.start();
});

document.addEventListener("turbo:load", function() {
  document.documentElement.removeAttribute("data-turbo-unloaded")
})

document.addEventListener("turbo:submit-start", function() {
  document.documentElement.setAttribute("data-turbo-loading", "1")
})
document.addEventListener("turbo:submit-end", function() {
  document.documentElement.removeAttribute("data-turbo-loading")
})

