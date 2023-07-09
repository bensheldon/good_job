# frozen_string_literal: true

module GoodJob
  class FrontendsController < ActionController::Base # rubocop:disable Rails/ApplicationController
    skip_after_action :verify_same_origin_request, raise: false

    STATIC_ASSETS = {
      css: {
        bootstrap: GoodJob::Engine.root.join("app", "frontend", "good_job", "vendor", "bootstrap", "bootstrap.min.css"),
        style: GoodJob::Engine.root.join("app", "frontend", "good_job", "style.css"),
      },
      js: {
        bootstrap: GoodJob::Engine.root.join("app", "frontend", "good_job", "vendor", "bootstrap", "bootstrap.bundle.min.js"),
        chartjs: GoodJob::Engine.root.join("app", "frontend", "good_job", "vendor", "chartjs", "chart.min.js"),
        es_module_shims: GoodJob::Engine.root.join("app", "frontend", "good_job", "vendor", "es_module_shims.js"),
        rails_ujs: GoodJob::Engine.root.join("app", "frontend", "good_job", "vendor", "rails_ujs.js"),
      },
    }.freeze

    MODULE_OVERRIDES = {
      application: GoodJob::Engine.root.join("app", "frontend", "good_job", "application.js"),
      stimulus: GoodJob::Engine.root.join("app", "frontend", "good_job", "vendor", "stimulus.js"),
    }.freeze

    def self.js_modules
      @_js_modules ||= GoodJob::Engine.root.join("app", "frontend", "good_job", "modules").children.select(&:file?).each_with_object({}) do |file, modules|
        key = File.basename(file.basename.to_s, ".js").to_sym
        modules[key] = file
      end.merge(MODULE_OVERRIDES)
    end

    before_action do
      expires_in 1.year, public: true
    end

    def static
      render file: STATIC_ASSETS.dig(params[:format].to_sym, params[:name].to_sym) || raise(ActionController::RoutingError, 'Not Found')
    end

    def module
      raise(ActionController::RoutingError, 'Not Found') if params[:format] != "js"

      render file: self.class.js_modules[params[:name].to_sym] || raise(ActionController::RoutingError, 'Not Found')
    end
  end
end
