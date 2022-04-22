# frozen_string_literal: true
module GoodJob
  class AssetsController < ActionController::Base # rubocop:disable Rails/ApplicationController
    skip_before_action :verify_authenticity_token, raise: false

    def self.js_modules
      @_js_modules ||= GoodJob::Engine.root.join("app", "assets", "modules").children.select(&:file?).each_with_object({}) do |file, modules|
        key = File.basename(file.basename.to_s, ".js").to_sym
        modules[key] = file
      end
    end

    before_action do
      expires_in 1.year, public: true
    end

    def es_module_shims_js
      render file: GoodJob::Engine.root.join("app", "assets", "vendor", "es_module_shims.js")
    end

    def bootstrap_css
      render file: GoodJob::Engine.root.join("app", "assets", "vendor", "bootstrap", "bootstrap.min.css")
    end

    def bootstrap_js
      render file: GoodJob::Engine.root.join("app", "assets", "vendor", "bootstrap", "bootstrap.bundle.min.js")
    end

    def chartjs_js
      render file: GoodJob::Engine.root.join("app", "assets", "vendor", "chartjs", "chart.min.js")
    end

    def rails_ujs_js
      render file: GoodJob::Engine.root.join("app", "assets", "vendor", "rails_ujs.js")
    end

    def scripts_js
      render file: GoodJob::Engine.root.join("app", "assets", "scripts.js")
    end

    def style_css
      render file: GoodJob::Engine.root.join("app", "assets", "style.css")
    end

    def modules_js
      module_name = params[:module].to_sym
      module_file = self.class.js_modules.fetch(module_name) { raise ActionController::RoutingError, 'Not Found' }
      render file: module_file
    end
  end
end
