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
import ChartController from "chart_controller";
Stimulus.register("chart", ChartController);
import LivePollController from "live_poll_controller";
Stimulus.register("live-poll", LivePollController);
import CheckboxToggleController from "checkbox_toggle_controller";
Stimulus.register("checkbox-toggle", CheckboxToggleController);

import "bootstrap_init";

document.addEventListener("turbo:load", function() {
  document.documentElement.removeAttribute("data-turbo-unloaded")
})

document.addEventListener("turbo:submit-start", function() {
  document.documentElement.setAttribute("data-turbo-loading", "1")
})
document.addEventListener("turbo:submit-end", function() {
  document.documentElement.removeAttribute("data-turbo-loading")
})
