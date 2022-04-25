/*jshint esversion: 6, strict: false */

import documentReady from "document_ready";
import showToasts from "toasts";
import renderCharts from "charts";
import Poller from "poller";

documentReady(function() {
  renderCharts();
  showToasts();
  Poller.start();
});
