/*jshint esversion: 6, strict: false */

import renderCharts from "charts";
import checkboxToggle from "checkbox_toggle";
import documentReady from "document_ready";
import showToasts from "toasts";
import setupPopovers from "popovers";
import LivePoll from "live_poll";

import { Application } from "stimulus";
import ThemeController from "theme_controller";
import MetricsController from "metrics_controller";
window.Stimulus = Application.start();
Stimulus.register("theme", ThemeController)
Stimulus.register("metrics", MetricsController)

documentReady(function() {
  renderCharts();
  showToasts();
  setupPopovers();
  checkboxToggle();

  const livePoll = new LivePoll
  livePoll.start();
});

