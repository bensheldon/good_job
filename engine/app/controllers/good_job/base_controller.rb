# frozen_string_literal: true
module GoodJob
  class BaseController < ActionController::Base # rubocop:disable Rails/ApplicationController
    protect_from_forgery with: :exception

    before_action -> { I18n.locale = :en }
  end
end
