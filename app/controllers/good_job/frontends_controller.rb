# frozen_string_literal: true

module GoodJob
  class FrontendsController < ActionController::Base # rubocop:disable Rails/ApplicationController
    protect_from_forgery with: :exception
    skip_after_action :verify_same_origin_request, raise: false

    def self.asset_path(*path)
      Engine.root.join("app/frontend/good_job", *path)
    end

    STATIC_ASSETS = {
      css: {
        bootstrap: asset_path("vendor", "bootstrap", "bootstrap.min.css"),
        style: asset_path("style.css"),
      },
      js: {
        bootstrap: asset_path("vendor", "bootstrap", "bootstrap.bundle.min.js"),
        chartjs: asset_path("vendor", "chartjs", "chart.min.js"),
        es_module_shims: asset_path("vendor", "es_module_shims.js"),
        turbo: asset_path("vendor", "turbo.js"),
      },
      svg: {
        icons: asset_path("icons.svg"),
      },
    }.freeze

    MODULE_OVERRIDES = {
      application: asset_path("application.js"),
      stimulus: asset_path("vendor", "stimulus.js"),
      turbo: asset_path("vendor", "turbo.js"),
    }.freeze

    def self.js_modules
      @_js_modules ||= asset_path("modules").children.select(&:file?).each_with_object({}) do |file, modules|
        key = File.basename(file.basename.to_s, ".js").to_sym
        modules[key] = file
      end.merge(MODULE_OVERRIDES)
    end

    before_action do
      expires_in 1.year, public: true
    end

    def static
      render file: STATIC_ASSETS.dig(params[:format]&.to_sym, params[:id]&.to_sym) || raise(ActionController::RoutingError, 'Not Found')
    end

    def module
      raise(ActionController::RoutingError, 'Not Found') if params[:format] != "js"

      render file: self.class.js_modules[params[:id]&.to_sym] || raise(ActionController::RoutingError, 'Not Found')
    end
  end
end
