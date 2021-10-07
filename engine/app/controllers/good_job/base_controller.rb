# frozen_string_literal: true
module GoodJob
  class BaseController < ActionController::Base # rubocop:disable Rails/ApplicationController
    protect_from_forgery with: :exception

    around_action do
      I18n.with_locale(:en) { yield }
    end
  end
end
