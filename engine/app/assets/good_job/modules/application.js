/*jshint esversion: 6, strict: false */

import renderCharts from "charts";
import checkboxToggle from "checkbox_toggle";
import documentReady from "document_ready";
import showToasts from "toasts";
import Poller from "poller";

documentReady(function() {
  renderCharts();
  showToasts();
  checkboxToggle();
  Poller.start();
});
