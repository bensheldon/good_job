# frozen_string_literal: true
module GoodJob
  class AssetsController < ActionController::Base # rubocop:disable Rails/ApplicationController
    skip_before_action :verify_authenticity_token, raise: false

    before_action do
      expires_in 1.year, public: true
    end

    def bootstrap_css
      render file: GoodJob::Engine.root.join("app", "assets", "vendor", "bootstrap", "bootstrap.min.css")
    end

    def bootstrap_js
      render file: GoodJob::Engine.root.join("app", "assets", "vendor", "bootstrap", "bootstrap.bundle.min.js")
    end

    def chartist_css
      render file: GoodJob::Engine.root.join("app", "assets", "vendor", "chartist", "chartist.css")
    end

    def chartist_js
      render file: GoodJob::Engine.root.join("app", "assets", "vendor", "chartist", "chartist.js")
    end

    def rails_ujs_js
      render file: GoodJob::Engine.root.join("app", "assets", "vendor", "rails_ujs.js")
    end

    def style_css
      render file: GoodJob::Engine.root.join("app", "assets", "style.css")
    end
  end
end
