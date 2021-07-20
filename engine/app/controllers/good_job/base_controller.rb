# frozen_string_literal: true
module GoodJob
  class BaseController < ActionController::Base # rubocop:disable Rails/ApplicationController
    protect_from_forgery with: :exception
  end
end
