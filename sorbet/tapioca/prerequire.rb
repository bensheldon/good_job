# typed: true
# frozen_string_literal: true

# "Descendants doesn't load for engines: https://github.com/Shopify/tapioca/issues/517
require 'rails/all'

# Necessary to load capybara/rails which creates a Rack::Builder with Rails.application
if Rails.application.nil?
  class Application < Rails::Application
  end
end
