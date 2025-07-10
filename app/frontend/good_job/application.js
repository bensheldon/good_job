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

document.addEventListener("turbo:submit-start", function() {
  document.documentElement.setAttribute("data-turbo-loading", "1")
})
document.addEventListener("turbo:submit-end", function() {
  document.documentElement.removeAttribute("data-turbo-loading")
})

import documentReady from "document_ready";
import renderCharts from "charts";
import checkboxToggle from "checkbox_toggle";
import showToasts from "toasts";
import setupPopovers from "popovers";
import LivePoll from "live_poll";

documentReady(function() {
  renderCharts();
  showToasts();
  setupPopovers();
  checkboxToggle();

  const livePoll = new LivePoll
  livePoll.start();
});

