# frozen_string_literal: true
module GoodJob
  class BaseController < ActionController::Base # rubocop:disable Rails/ApplicationController
    protect_from_forgery with: :exception

    around_action :switch_locale

    private

    def switch_locale(&action)
      I18n.with_locale(:en, &action)
    end
  end
end
